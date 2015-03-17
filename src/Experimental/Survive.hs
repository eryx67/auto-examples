{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Arrows #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE DeriveFunctor #-}

module Main where

import Control.Auto
import Control.Auto.Blip
import Control.Auto.Blip.Internal
import Control.Auto.Collection
import Control.Auto.Core
import Control.Auto.Interval
import Control.Auto.Run
import Control.Lens
import Control.Monad                (unless, guard, mfilter)
import Control.Monad.Fix
import Data.Foldable
import Data.IntMap.Strict           (IntMap, Key)
import Data.List                    (sortBy)
import Data.Map.Strict              (Map)
import Data.Maybe
import Data.Ord
import Data.Serialize
import Data.Traversable             (sequence)
import Debug.Trace
import GHC.Generics
import Linear
import Prelude hiding               ((.), id, elem, any, sequence, concatMap, sum)
import System.Console.ANSI
import System.IO
import qualified Data.IntMap.Strict as IM
import qualified Data.Map.Strict    as M

data Dir = DUp | DRight | DDown | DLeft
         deriving (Show, Eq, Enum, Ord, Read, Generic)

data Usable = Sword | Bow | Bomb | Wall
            deriving (Show, Eq, Enum, Ord, Read)

data Item = Potion
          deriving (Show, Eq, Enum, Ord, Read)

data Cmd = CMove Dir
         | CAtk Usable Dir
         | CUse Item
         deriving (Show, Eq, Ord, Read)

data EntResp = ERAtk Double Point
             | ERShoot Dir
             | ERBomb Dir
             | ERBuild Dir
             deriving (Show, Eq, Ord, Read, Generic)

data EntComm = ECAtk Double
             deriving (Show, Eq, Ord, Read, Generic)

data Entity = EPlayer | EBomb | EWall
            deriving (Show, Eq, Enum, Ord, Read, Generic)

data EntityInput a = EI { _eiData  :: a
                        , _eiPos   :: Point
                        , _eiComm  :: [(Key, EntComm)]
                        , _eiWorld :: EntityMap
                        } deriving (Show, Eq, Ord, Read, Functor)


type Point         = V2 Int
type GameMap       = Map Point [Entity]
type EntityMap     = IntMap (Point, Entity)
type EntityOutput  = ((Point, Entity), [EntResp])

instance Serialize EntResp
instance Serialize EntComm
instance Serialize Dir
instance Serialize Entity

instance Serialize a => Serialize (EntityInput a) where
    put (EI x p c w) = put x *> put p *> put c *> put w
    get              = EI <$> get <*> get <*> get <*> get

instance Applicative EntityInput where
    pure x = EI x zero mempty mempty
    EI f p0 c0 w0 <*> EI x p1 c1 w1 = EI (f x) (p0 ^+^ p1) (c0 ++ c1) (w0 <> w1)

instance Semigroup a => Semigroup (EntityInput a) where
    (<>) = liftA2 (<>)

instance Monoid a => Monoid (EntityInput a) where
    mempty  = pure mempty
    mappend = liftA2 mappend


makePrisms ''Cmd
makePrisms ''EntResp
makePrisms ''EntComm
makeLenses ''EntityInput

mapSize :: V2 Int
mapSize = V2 70 20

startPos :: V2 Int
startPos = (`div` 2) <$> mapSize

dirToV2 :: Dir -> V2 Int
dirToV2 dir = case dir of
                DUp    -> V2 0    1
                DRight -> V2 1    0
                DDown  -> V2 0    (-1)
                DLeft  -> V2 (-1) 0

bomb :: Monad m => Dir -> Interval m (EntityInput ()) EntityOutput
bomb dir = proc _ -> do
    motion <- fromInterval zero . onFor 6 . pure (dirToV2 dir) -< ()
    onFor 10 -< ((motion, EBomb), [])


wall :: Monad m => Interval m (EntityInput ()) EntityOutput
wall = proc ei -> do
    let damage = sumOf (eiComm . traverse . _2 . _ECAtk) ei
    die <- became (<= 0) . sumFrom 3 -< negate damage
    before -< (((zero, EWall), []), die)

player :: Monad m => Interval m (EntityInput Cmd) EntityOutput
player = proc (EI inp p _ world) -> do
    moveB            <- modifyBlips dirToV2
                      . emitJusts (preview _CMove)   -< inp

    (atkMvB, moveB') <- splitB isAtkMv               -< (,(p, world)) <$> moveB

    atkB             <- modifyBlips toResp
                      . emitJusts (preview _CAtk)    -< inp
    let allAtkB = atkB `mergeL` (ERAtk 1.0 . (+p) . fst <$> atkMvB)

    move <- fromBlips zero -< fst <$> moveB'
    allAtk <- fromBlipsWith [] (:[]) -< allAtkB

    toOn -< ((move, EPlayer), allAtk)
  where
    isAtkMv :: (Point, (Point, EntityMap)) -> Bool
    isAtkMv (m,(p,em)) = any (\(p',e) -> p' == (p+m) && attackIt e) em
    toResp :: (Usable, Dir) -> EntResp
    toResp (u,d) = case u of
                     Sword -> ERAtk 1.0 (dirToV2 d)
                     Bow   -> ERShoot d
                     Bomb  -> ERBomb d
                     Wall  -> ERBuild d
    attackIt e =     case e of
                   EPlayer -> False
                   EWall   -> True
                   EBomb   -> False


locomotor :: Monad m
          => Point
          -> Interval m (EntityInput a) EntityOutput
          -> Interval m (EntityInput a) EntityOutput
locomotor p0 entA = proc inp@(EI _ _ _ world) -> do
    outp <- entA -< inp
    pos  <- fst <$> accum f (p0, False) -< (world, maybe zero (fst.fst) outp)
    id    -< set (_1._1) pos <$> outp
  where
    f :: (Point, Bool) -> (EntityMap, Point) -> (Point, Bool)
    f (p, mvd) (world, motion) = (restrict (p ^+^ motion), True)
      where
        world' = IM.mapMaybe getBlockers world
        restrict p' | not mvd          = p'
                    | p' `elem` world' = clamp' p
                    | otherwise        = clamp' p'
        clamp' | clamp p == p = clamp
               | otherwise    = id
    clamp = liftA3 (\mn mx -> max mn . min mx) (V2 0 0) mapSize
    getBlockers (pos, ent) | isBlocking ent = Just pos
                           | otherwise      = Nothing
    isBlocking ent = case ent of
                       EPlayer -> True
                       EWall   -> True
                       EBomb   -> False

game :: MonadFix m => Auto m Cmd GameMap
game = proc inp -> do
    rec let pInp = maybe (pure inp)
                         (set eiData inp)
                         (IM.lookup (-1) (IM.unionWith (<>) entInp attacks))

        pOut@((pPos,pEnt), pResp) <- fromJust <$> locomotor startPos player -< pInp

        newEnts <- emitOn (not . null)          -< (pPos,) <$> pResp

        attacks <- arr collectAttacks -< entOuts'

        entInp  <- arr mkEntInp -< fst <$> entOuts'

        entOuts <- dynMapF makeEntity (pure ()) -< (IM.unionWith (<>) entInp attacks, newEnts)

        entOutsD <- delay IM.empty -< entOuts
        let entOuts' = IM.insert (-1) pOut entOutsD


    let entMap = M.fromListWith (<>)
               . IM.elems
               . fmap (second (:[]) . fst)
               . IM.insert (-1) pOut
               $ entOuts

    id -< entMap
  where
    mkEntInp :: IntMap (Point, Entity) -> IntMap (EntityInput ())
    mkEntInp ents = (`IM.mapWithKey` ents) $ \i (p,_) ->
                      (EI () p [] (IM.delete i ents))
    makeEntity :: Monad m
               => (Point, EntResp)
               -> Interval m (EntityInput ()) EntityOutput
    makeEntity (pPos, er) = case er of
                              ERBomb dir  -> locomotor placed (bomb dir)
                              ERBuild dir -> locomotor placed wall
                              _           -> off
      where placed = place pPos er

    place :: Point -> EntResp -> Point
    place p er = case er of
                   ERAtk i disp -> p ^+^ disp
                   ERBomb  dir  -> p
                   ERBuild dir  -> p ^+^ dirToV2 dir
                   ERShoot dir  -> p ^+^ dirToV2 dir

    collectAttacks :: Monoid a => IntMap EntityOutput -> IntMap (EntityInput a)
    collectAttacks ents = fmap (\as -> set eiComm as mempty) $
      (`IM.mapWithKey` ents) $ \i ((p,_),_) ->
        let filtEnts = IM.delete i ents
            atks = (`IM.mapWithKey` filtEnts) $ \i' ((p',_),ers) ->
                     flip mapMaybe ers $ \er -> do
                       ERAtk a _ <- Just er
                       guard $ place p' er == p
                       Just (ECAtk a)
        in  concatMap sequence $ IM.toList atks

handleCmd :: (Serialize b, Monoid b, Monad m)
          => Auto m Cmd b
          -> Auto m (Maybe Cmd) b
handleCmd a0 = holdWith mempty . perBlip a0 . onJusts

renderBoard :: GameMap -> String
renderBoard mp = unlines . reverse
               $ [[ charAt x y | x <- [0..xMax] ] | y <- [0..yMax]]
  where
    charAt x y = fromMaybe '.' $ do
      es <- M.lookup (V2 x y) mp
      fmap entChr . listToMaybe . sortBy (comparing entPri) $ es
    xMax = view _x mapSize
    yMax = view _y mapSize
    entChr e = case e of
                 EPlayer -> '@'
                 EBomb   -> 'o'
                 EWall   -> '#'
    entPri e = case e of
                 EPlayer -> 0 :: Int
                 EBomb   -> 10
                 EWall   -> 1

parseCmd :: Auto m Char (Blip (Maybe Cmd))
parseCmd = go Nothing
  where
    go Nothing  = mkAuto_ $ \x -> case x of
                    'h' -> (Blip (Just (CMove DLeft )) , go Nothing     )
                    'j' -> (Blip (Just (CMove DDown )) , go Nothing     )
                    'k' -> (Blip (Just (CMove DUp   )) , go Nothing     )
                    'l' -> (Blip (Just (CMove DRight)) , go Nothing     )
                    '5' -> (Blip (Just (CUse Potion )) , go Nothing     )
                    '1' -> (NoBlip                     , go (Just Sword))
                    '2' -> (NoBlip                     , go (Just Bow  ))
                    '3' -> (NoBlip                     , go (Just Bomb ))
                    '4' -> (NoBlip                     , go (Just Wall ))
                    _   -> (Blip Nothing               , go Nothing     )
    go (Just u) = mkAuto_ $ \x -> case x of
                    'h' -> (Blip (Just (CAtk u DLeft )), go Nothing     )
                    'j' -> (Blip (Just (CAtk u DDown )), go Nothing     )
                    'k' -> (Blip (Just (CAtk u DUp   )), go Nothing     )
                    'l' -> (Blip (Just (CAtk u DRight)), go Nothing     )
                    _   -> (Blip Nothing               , go Nothing     )


main :: IO ()
main = do
    hSetBuffering stdin NoBuffering
    renderStdout (M.singleton startPos [EPlayer])
    _ <- runM generalize getChar process $ holdWith M.empty
                                         . perBlip (handleCmd game)
                                         . parseCmd
    return ()
  where
    renderStdout mp = do
      -- clearScreen
      putStrLn ""
      putStrLn (renderBoard mp)
    process mp = do
      unless (M.null mp) $ renderStdout mp
      Just <$> getChar


generalize :: Monad m => Identity a -> m a
generalize = return . runIdentity
