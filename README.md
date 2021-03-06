auto-examples
=============

Various examples to demonstrate features of the in-development [auto][]
library, and also as guides for writing your own applications.  API subject to
much change.  The online development documentation is kept at
<https://mstksg.github.io/auto>.

[auto]: https://github.com/mstksg/auto

Before reading this, check out the [auto README][arm] for a brief overview of
the *auto* library, and its main goals and philosophies :)

[arm]: https://github.com/mstksg/auto/blob/master/README.md

Installation instructions:

~~~bash
# clone this examples repository
$ git clone https://github.com/mstksg/auto-examples
$ cd auto-examples

# set up the sandbox, pointing to the library source on-disk
$ cabal sandbox init

# install
$ cabal install
# ghcjs examples, if desired
$ cabal install --ghcjs
~~~

And the executables should all be in `./.cabal-sandbox/bin` of the
`auto-examples` dir.

Examples
--------

### [hangman][]

[hangman]: https://github.com/mstksg/auto-examples/blob/master/src/Hangman.hs

A fully featured command-line hangman game.  Made to demonstrate many
high-level features, like the composition of locally stateful autos with
proc-do notation, implicit serializability, switching, and usage of
`interact`.  Lays out some pretty common idioms and displays some design
methodology.

Note the lack of a global "hangman state".  All the components of the state
--- the current word, the wrong guesses, the player scores, etc. --- are
isolated from each other and only interact when needed.  The `Puzzle` type only
contains information for the console to display the current "output" of the
puzzle --- it doesn't even contain the solution.

Also, note the principled reading and saving of the game auto using `readAuto`
and `writeAuto`.

Demonstrates as well some high concepts like building an `Auto` over a monad
like `Rand`, and then "sealing away" the randomness.  `hangmanRandom` uses an
underlying monad to generate new words, and `hangman` "seals away" the
randomness of the underlying monad; the entropy is self-contained only in the
parts that need it.

Also uses `interactAuto` as a high level wrapper to "run" an `Auto` on stdin.

Admittedly it's a lot "longer" in terms of lines of code than the simple
explicit-state-passing version (even without the gratuitous whitespace and
commenting).  Part of this is because the idea of Hangman is pretty simple.
But I really feel like the whole thing "reads" well, and is in a more
understandable high-level declarative/denotative style than such an approach.

### [logger][]

[logger]: https://github.com/mstksg/auto-examples/blob/master/src/Logger.hs

Mostly used to demonstrate "automatic serialization".  Using the `serializing`
combinator, we transform a normal auto representing a logging process into an
auto that automatically, implicitly, and constantly serializes itself...and
automatically re-loads the saved state on the program initialization.

Demonstrates also `resetFrom`, which is a basic switcher that allows an `Auto`
to "reset" itself through an output blip stream.

Also heavy usage of "blip stream" logic and intervals to sort out and manage
the stream of inputs into streams that do things and create outputs.

### [chatbot][]

[chatbot]: https://github.com/mstksg/auto-examples/blob/master/src/Chatbot.hs

Lots of concepts demonstrated here.  In fact, this was one of the motivating
reasons for the entire *auto* library in the first place.

First, a "real world" interface; the Auto is operated and run over an IRC
server using the [simpleirc][] library.  The library waits on messages, runs
the Auto, sends out the outputs, and stores the new Auto.

[simpleirc]: http://hackage.haskell.org/package/simpleirc

Secondly, the "monoidal" nature of Auto is taken full advantage of here. Each
individual bot module is a full fledged bot (of type `ChatBot m`, or `ChatBot'
m`).  The "final" bot is the `mconcat`/monoid sum of individual modules.  The
monoid nature means that pairs of bots can be combined and modified together
and combined with other bots, etc.

Like legos! :D

Third --- there is no "global chatbot state".  That is, *every module*
maintains *its own internal state*, isolated and unrelated to the other
modules.  In the "giant state monad" approach, *even with* using zoom and
stuff from lens...every time you add a stateful module, you *have to change
the global state type*.  That is, you'd have to "fit in" the room for the new
state in your global state type.

In this way, adding a module is as simple as just adding another `(<>)` or
item to the `mconcat` list.  Each module is completely self-contained and
maintains its own state; adding a module does not affect a single aspect of
any other part of the code base.

Fourth, serializing individual components of wires "automatically".  We don't
serialize the entire chatbot; we can simply serialize individual Auto
components in the chain.  This is because of the type of `serializing' fp`:

```haskell
serializing' fp :: MonadIO => Auto m a b -> Auto m a b
```

It basically takes an Auto and returns a Auto that is identical in every
way...except self-reloading and self-serializing.  Whenever you use that
transformed Auto as a component of any other one, that individual component
will be self-reloading and self-serializing, even if it's embedded deep in a
complex composition.

```haskell
f (serializing' fp a1) (serializing' fp a2)
= serializing' fp (f a1 a2)
```

Also, there is the demonstration of using "lifters", like `perRoom` to
transform a `ChatBot` who can only send messages back to the channel it
received messages to a `ChatBot` who can send messages to any channel.  They
behave the same way --- but now they can be combined with other such bots.  In
this way, you can write "limited bots", and still have them "play well" and
combine with other bots --- inspired by the principles of Gabriel Gonzalez's
[Functor Design Pattern][fdp].

[fdp]: http://www.haskellforall.com/2012/09/the-functor-design-pattern.html

The individual bots themselves all demonstrate usage of common Auto
combinators, like `accum` (which modifies the state with input continually,
with the given function) --- also much usage of the `Blip` mechanism and
semantics --- much of the bots respond to "blips" --- like detected user
commands, and the day changing.

Working with streams of blips, "scanning over them" (like `accum` but with
blips), and consolidating blip streams back into normal streams are all
demonstrated.

### [recursive][]

[recursive]: https://github.com/mstksg/auto-examples/blob/master/src/Recursive.hs

Three simple demonstrations of using recursive bindings.  Basically, this
allows you even greater power in specifying relationships, in a graph-like
style.  The library (with the help of proc syntax) basically "ties the loop"
*for* you (if it's possible).

The first demonstration is a Fibonacci sequence, to demonstrate how to
basically step through a recursive series without explicit memoization of
previous values.  They're all "accessible" using `delay`, in constant space.

The second demonstration is a power-of-twos series, using the definition `z_n
= z_(n-1) + z_(n-1)`.   Not really anything special, but it's trippy to see
a variable used in a recursive definition of itself!

The third is a neat implementation of the [PID controller algorithm][pid] in
order to tune an opaque system to a desired setpoint/goal response.

[pid]: http://en.wikipedia.org/wiki/PID_controller

The algorithm itself is explained in the program, but one thing important to
note is that this example clearly shows a demonstration on how to "wrangle"
recursive bindings in a way that makes sense.

The main algorithm is this:

~~~haskell
rec let err        = target - response

    cumulativeSum <- sumFrom 0 -< err
    changes       <- deltas    -< err

    let adjustment = kp * err
                   + ki * cumulativeSum
                   + kd * fromMaybe 0 changes

    control  <- sumFrom c0 -< adjustment

    response <- blackbox   -< control
~~~

This looks a lot like how you would describe the algorithm from a high level.
"The error is the difference between the goal and the response, and the
cumulative sum is the cumulative sum of the errors.  The changes is the deltas
between `err`s.  The adjustment is each term multiplied by a constant...the
control is the cumulative sum of the adjustments, and the response is the
result of feeding the control to the black box system.

This actually doesn't work initially...because...how would you get it started?
Everything depends on everything else.

The key is that we need to have one value that can get its "first value"
without any other input.  That is our "base case", which allows for the
knot-tying to work.

~~~haskell
control      <- sumFromD c0       -< adjustment
~~~

`sumFromD` is like `sumFrom`, except it outputs `c0` on its first step, before
adding anything.  Now, `control` is a value that doesn't "need anything" to
get its first/immediate value, so everything works!

Alternatively, we can also:

~~~haskell
currResponse <- system . delay c0 -< control
~~~

`delay` is like `id`, except it outputs `c0` on its first step (and delays
everything by one).  It can output `c0` before receiving anything.  Again, the
same goal is reached, and either of these fixes allow for the whole thing to
work.

This example is intended to be a nice reference sheet when working with
recursive bindings.

### [todo][]

[todo]: https://github.com/mstksg/auto-examples/blob/master/src/Todo.hs

Roughly following the [TodoMVC][] specs; a todo app with the ability to add,
complete, uncomplete, delete, etc.

[TodoMVC]: http://todomvc.com

The actual logic is [here][todo]; a command line client is at
[TodoCmd.hs][], and a javascript client using ghcjs that uses the TodoMVC
style sheets and guidelines are at [TodoJS.hs][].

[TodoCmd.hs]: https://github.com/mstksg/auto-examples/blob/master/src/TodoCmd.hs
[TodoJS.hs]: https://github.com/mstksg/auto-examples/blob/master/src/TodoJS.hs

It demonstrates the architecture of a simple app:  Your app itself is an
`Auto`, and your GUI elements/command line parsers simply drop inputs to the
`Auto` in a queue to be processed one-by-one; the outputs are then rendered.

The app is structured so that the input goes in in one channel, and is
immediately "forked" into several blip streams.  Each stream does its work,
and in the end, they results are all recombined together to create the "big
picture".

Also a good usage of dynamic collections, especially `dynMapF`, to dynamically
store `Auto`s for each task, generating new id's/addresses on the fly while
spawning new tasks.

The [demo is online][todojs], to try out!

[todojs]: https://mstksg.github.com/auto-examples/todo


### [life][]

[life]: https://github.com/mstksg/auto-examples/blob/master/src/Life.hs

[Conway's Game of Life][cgol] implementation.  Demonstration of
non-interactive automation/simulation/cellular automaton.  In the technical
aspects, a demonstration of the `rec`/`ArrowLoop` mechanisms for recursive,
graph-like Auto connections.

[cgol]: http://en.wikipedia.org/wiki/Conway's_Game_of_Life

I consider this to be another compelling demonstration of the power of
denotative style.  The thing is laid out very graph-like, using recursive
bindings, and the entire "step" is, at the (abstracted away) low-level,
finding a fixed point of a graph of functions.  Some nice practice with the
various `Blip` combinators, as well!

I might one day expand this to use a GUI, so you it can also show graphics
applications.

Experimental
------------

Some things I've just been working on...they aren't really here as good
examples yet, but I'm working on making them fit into the bigger picture :)

### [connect4][]

[connect4]: https://github.com/mstksg/auto-examples/blob/master/src/Experimental/Connect4.hs

This example has a lot of distinct things involved, and I'm still sort of
working it out for maximum demonstrative purposes.

1.  It has an AI algorithm -- an implementation of minimax w/ alpha-beta
    pruning -- that carries the Auto of the game board with it...and
    "progresses it" in a different way down every branch of the game tree.
    Instead of passing a parameter with the game state, it passes around "the
    game itself", and "runs"/re-clones it for every new branch of the game
    tree.

2.  It demonstrates a safe usage of `lastVal`/`delay`, which is necessary for
    working well with recursive bindings.  Explicitly using `delay` or
    `lastVal` lets you really explicitly say what depends on what, in terms of
    time, so you don't go into an infinite loop.

3.  It uses `mux` and `gather`, which are Auto "multiplexers" and "gatherers".
    It uses `mux` to basically manage the pool of "Controllers" (players in
    the game), and "run" the desired one, dynamically.  `gather` does a
    similar thing, except it gathers all of the results so far in an output
    Map.

    These are powerful tools for managing dynamic collections of Autos, and
    routing the proper messages to the proper ones that need them.

4.  It uses `fastForward`, which allows you to turn an `Auto m a (Maybe b)`
    into an `Auto m a b` by "skipping over" the `Nothing`s,
    manipulating/warping time to fit your needs.  This is used to allow the
    `game'` auto to "ask for input" when it needs input (on `Just request`)
    and "skip over and happily run along" when it doesn't (on `Nothing`).

    (Not sure how useful of an abstraction this is at this point...it might be
    better to let the actual driver/runner handle it.)

