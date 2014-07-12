Node async-profile profiles CPU usage in node apps.

It lets you see at a glance how much CPU time is being taken up by a given part of your app, even if that
part of your app is also doing asynchronous IO.

I built it at [Bugsnag](https://bugsnag.com) to help us understand why our background processors were
using 100% CPU all the time.

# Installation

This currently only works on node 0.10. 0.11 support should be easy to add, and much lower overhead :).


```
npm install async-profile
```

# Usage

When you create a new AsyncProfile it automatically profiles work done by any asynchronous callbacks
created in the current 'tick', and then writes the results to stdout.

```javascript
var AsyncProfile = require('async-profile')

// First set up an isolated callback (using any function that executes its callback asynchronously).
// Any callbacks created in this callback will be profiled transitively.
process.nextTick(function () {

    // Now start profiling. The profile will include all
    // callbacks created while the current callback is running.
    new AsyncProfile()

    // Finally queue up the work to be done asynchronously.
    process.nextTick(doWork);
})
```

## Interpreting the output

The output looks something like this: (taken from a profile of [bugsnag](https://bugsnag.com)'s backend)

```
total: 1.823ms (in 2.213ms real time, max concurrency: 1.2, wait time: 3.688ms)
0.879: 0.011ms    at Function.Project.fromCache (/0/bugsnag/event-worker/lib/project.coffee:12:16) (0.072ms)
0.970: 0.363ms    [no mark] (0.250ms)
1.589: 0.002ms        at /0/bugsnag/event-worker/workers/notify.coffee:29:13 (0.000ms)
1.622: 0.010ms        at /0/bugsnag/event-worker/workers/notify.coffee:30:13 (0.000ms)
1.668: 0.043ms        at Event.hash (/0/bugsnag/event-worker/lib/event/event.coffee:238:16) (0.061ms)
1.780: 0.064ms          at /0/bugsnag/event-worker/lib/event/event.coffee:246:21 (0.098ms)
2.016: 0.064ms            at Object.exports.count (/0/bugsnag/event-worker/lib/throttling.coffee:12:14) (0.122ms)
2.250: 0.052ms            REDIS EVAL SCRIPT (0.123)
2.506: 0.166ms                at throttleProjectEvent (/0/bugsnag/event-worker/lib/throttling.coffee:125:14) (0.295ms)
2.433: 0.002ms                at throttleProjectEvent (/0/bugsnag/event-worker/lib/throttling.coffee:125:14) (0.000ms)
2.211: 0.002ms              at throttleAccountEvent (/0/bugsnag/event-worker/lib/throttling.coffee:73:14) (0.000ms)
1.947: 0.002ms            at Object.exports.count (/0/bugsnag/event-worker/lib/throttling.coffee:12:14) (0.000ms)
1.593: 0.001ms        at Event.hash (/0/bugsnag/event-worker/lib/event/event.coffee:238:16) (0.000ms)
0.775: 0.003ms    at Function.Project.fromCache (/0/bugsnag/event-worker/lib/project.coffee:12:16) (0.000ms)
```

The first line contains 4 numbers:

* `total` — the total amount of time spent running CPU.
* `real time` — the amount of time between the first callack starting and the last callback ending.
* `max concurrency` — is just `real time / total`. Assuming that node is single threaded, and you want to peg the CPU at 100%, how
    many tasks like this could run concurrently.
* `wait time` — the sum of the times between each callback being created and being called. High wait times can happen either because
    you're waiting for a lot of parallel IO events, or because you're waiting for other callbacks to stop using the CPU.

Each subsequent line contains 4 bits of information:
* `start`: The time since you called `new AsyncProfile()` and when this callback started running.
* `cpu time`: The amount of CPU time it took to execute this callback.
* `location`: The point in your code at which this callback was created. (see also [marking](#marking)).
* `overhead`: The amount of CPU time it took to calculate `location` (see also [speed](#speed)) which has been subtraced from the `cpu time` column.

Additionally the indentation lets you re-construct the tree of callbacks.

## Marking

Sometimes it's hard to figure out exactly what's running when, particularly as the point at which the underlying async callback is created might not
correspond to the location of a callback function in your code. At any point while the profiler is running you can mark the current callback to
make it easy to spot in the profiler output.

```javascipt
AsyncProfile.mark 'SOMETHING EASY TO SPOT'
```

For example in the above output, I've done that for the callback that was running `redis.eval` and marked it as `'REDIS EVAL SCRIPT'`.

## Speed

Like all profilers, this one comes with some overhead. In fact, by default it has so much overhead that I had to calculate it and then subtract it from the results :p.

There is some overhead not included in the overhead numbers, but it should hopefully be fairly insignficant (1-10μs or so per async call) and also not included in the profiler output.

You can make the profiler faster by creating it with the fast option. This disables both stack-trace calculation, and overhead calculation.

```javascript
new AsyncProfile({fast: true})
```

## Stopping
*also known as "help, it's not displaying anything"*

If your process happens to make an infinite cascade of callbacks (often this happens with promises libraries), then you will have to manually stop the profiler manually. For example using a promise you might want to do something like:

```javascript

var p = new AsyncProfile()
Promise.try(doWork).finally(function () {
    p.stop();
});
```

## Custom reports

You can pass a callback into the constructor to generate your own output. The default callback looks like this:

```javascript
new AsyncProfile({
    callback: function (result) {
        result.print();
    }
);
```

You have access to all the useful properties of the profiler on the result object.

# Common problems

## No output is produced

Try manually [stopping](#stopping) the profiler. You might have an infinite chain of callbacks, or no callbacks at all.

## Some callbacks are missing

We're using [`async-listener`](https://www.npmjs.org/package/async-listener) under the hood, and it sometimes can't "see" beyond
some libraries (like redis or mongo) that use connection queues.

The solution is to manually create a bridge over the asynchronous call. You can look at the code to see how I did it for mongo and
redis. Pull requests are welcome.

## Crashes on require with async-listener polyfill warning.

Either you're using node 0.11 (congrats!) or you're including
[`async-listener`](https://www.npmjs.org/package/async-listener) from multiple
places.

You can fix this by sending a pull request :).


# Meta-fu

async-profile is licensed under the MIT license. Comments, pull-requests and issue reports are welcome.

