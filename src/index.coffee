Result = require './result'
Polyfills = require './polyfill'

class AsyncProfile

  @active = []

  constructor: (opts) ->
    @callback = opts?.callback || (result) -> result.print()
    @fast = opts?.fast || false
    @awaiting = 0
    @ticks = []
    @tick  = null
    @start = null
    @end   = null

    AsyncProfile.active.push(@)

    @listener = process.addAsyncListener(
      () => @create()
      {
        before: (_, tick) => @before(tick)
        after: (_, tick) => @after(tick)
        error: (tick, err) => @after(tick)
      }
    )

  # Create a new tick to be called later
  create: ->
    return if @end
    overhead = if @tick && !@fast
                process.hrtime()
    @awaiting += 1
    tick = {queue: process.hrtime(), parent: @tick, overhead: [0,0]}
    @start ||= tick.queue
    tick.stack = @stack() unless @fast
    @ticks.push(tick)
    if overhead
      overhead = process.hrtime(overhead)
      @tick.overhead[0] += overhead[0]
      @tick.overhead[1] += overhead[1]

    tick

  # Called at the beginning of a tick
  before: (tick) ->
    return if @end
    @awaiting -= 1
    tick.previous = @tick
    @tick = tick
    @tick.start = process.hrtime()

  # Called at the end of a tick
  after: (tick) ->
    return if @end
    @tick.end ||= process.hrtime()

    @stop() if @awaiting == 0
    previous = @tick.previous
    @tick.previous = null
    @tick = previous

  # Cheaply capture the stack (without file/line info)
  stack: ->
    orig = Error.prepareStackTrace
    Error.prepareStackTrace = (_, stack) -> stack
    err = new Error()
    Error.captureStackTrace(err, arguments.callee)
    stack = err.stack
    Error.prepareStackTrace = orig
    return err.stack

  # Mark the current tick (see also @mark)
  mark: (context) ->
    if @tick
      @tick.mark = context

  # Stop profiling and call the callback
  stop: ->
    return if @end
    @tick.end ||= process.hrtime() if @tick
    @end = @tick?.end || process.hrtime()
    process.removeAsyncListener(@listener)

    i = AsyncProfile.active.indexOf(@)
    AsyncProfile.active.splice(i, 1)

    process.nextTick =>
      @callback(new Result(@))

  # Profile the provided function
  @profile: (fn, args...) ->
    process.nextTick(() ->
      new AsyncProfile(args...)
      process.nextTick(fn)
    )

  # mark the current tick
  @mark: (context) ->
    for profile in AsyncProfile.active
      profile.mark(context)

  # stop any current profilers
  @stop: (context) ->
    for profile in AsyncProfile.active
      profile.stop(context)

module.exports = AsyncProfile
