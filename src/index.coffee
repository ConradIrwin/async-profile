require 'async-listener'
wrapCallback = require 'async-listener/glue'

class AsyncProfile
  @current = null

  @bridge: (fn) ->
    () ->
      index = arguments.length - 1
      if typeof arguments[index] == "function"
        arguments[index] = wrapCallback(arguments[index])
      fn.apply(this, arguments)

  @bridgeRedisPackage: (redis) ->
    fn = redis.RedisClient.prototype.send_command
    redis.RedisClient.prototype.send_command = (command, args, callback) ->
      if Array.isArray(args)
        if typeof callback == 'function'
          callback = AsyncProfile.wrap(callback)
        else if !callback
          index = args.length - 1
          if typeof args[index] == "function"
            args[index] = AsyncProfile.wrap(args[index])

      fn.call(this, command, args, callback)

  @bridgeMongoDb: (db) ->
    db._executeInsertCommand = AsyncProfile.bridge(db._executeInsertCommand)
    db._executeQueryCommand  = AsyncProfile.bridge(db._executeQueryCommand)
    db._executeUpdateCommand = AsyncProfile.bridge(db._executeUpdateCommand)
    db._executeRemoveCommand = AsyncProfile.bridge(db._executeRemoveCommand)

  @wrap: (fn) ->
    wrapCallback(fn)

  constructor: (@opts) ->
    if !@opts
      @opts = {}
    if !@opts.callback
      @opts.callback = (result) -> result.print()

    @awaiting = 0
    @ticks = []
    @tick = null
    @start = process.hrtime()
    AsyncProfile.current = @

    @listener = process.createAsyncListener(
      () =>
        return if @end
        overhead = if @tick && !@opts.fast
                    process.hrtime()

        @awaiting += 1
        tick = {queue: process.hrtime(), parent: @tick, overhead: [0,0]}
        tick.stack = @stack() if !@opts.fast
        @ticks.push(tick)
        if overhead
          overhead = process.hrtime(overhead)
          @tick.overhead[0] += overhead[0]
          @tick.overhead[1] += overhead[1]

        tick

      {
        before: (_, storage) => @before(storage)
        after: (_, storage) => @after(storage)
        error: (storage, err) => @after(storage)
      }
    )
    process.addAsyncListener(@listener)

  stack: ->
    orig = Error.prepareStackTrace
    Error.prepareStackTrace = (_, stack) -> stack
    err = new Error()
    Error.captureStackTrace(err, arguments.callee)
    stack = err.stack
    Error.prepareStackTrace = orig
    return err.stack

  before: (storage) ->
    return if @end
    @awaiting -= 1
    storage.previous = @tick
    @tick = storage
    @tick.start = process.hrtime()
    AsyncProfile.current = @

  after: (storage) ->
    return if @end
    @tick.end ||= process.hrtime()
    AsyncProfile.current = null
    if @awaiting == 0
      @end = @tick.end
      process.removeAsyncListener(@listener)
      @callback(@)
    previous = @tick.previous
    delete @tick.previous
    @tick = previous

  @mark: (context) ->
    if @current
      @current.mark(context)

  mark: (context) ->
    if @tick
      @tick.mark = context

  header: () ->
    sum = [0, 0]
    wait = [0, 0]
    min = [Infinity, Infinity]
    max = [0, 0]
    for _, tick of @ticks
      continue if tick.ignore

      if tick.queue[0] < min[0] || (tick.queue[0] == min[0] && tick.queue[1] < min[1])
        min = tick.queue
      if tick.end[0] > max[0] || (tick.end[0] == max[0] && tick.queue[1] > max[1])
        max = tick.end

      sum[0] += tick.end[0] - tick.start[0] - tick.overhead[0]
      sum[1] += tick.end[1] - tick.start[1] - tick.overhead[1]
      wait[0] += tick.start[0] - tick.queue[0]
      wait[1] += tick.start[1] - tick.queue[1]

    total = [sum[0] + wait[0], sum[1] + wait[1]]

    "total: #{@time(sum)}ms (in #{@diff(max, min)}ms real time, max concurrency: #{(@diff(max, min) / @time(sum)).toFixed(1)}, await time: #{@time(wait)}ms)"

  print: (parent=null, from=0, indent="") ->

    if parent == null
      for i in [from...@ticks.length]
        @ticks[i].ignore = true unless @ticks[i].queue && @ticks[i].start && @ticks[i].end

      console.log @header()

    for i in [from...@ticks.length]
      tick = @ticks[i]
      continue if tick.parent != parent
      continue if tick.ignore

      if tick.stack && !tick.mark
        tick.mark = @getLineFromStack(tick.stack)

      time = [tick.end[0] - tick.start[0] - tick.overhead[0], tick.end[1] - tick.start[1] - tick.overhead[1]]

      console.log "#{@diff(tick.start, @start)}: #{@time(time)}ms #{indent} #{tick.mark || "[no mark]"} (#{@time(tick.overhead)})  "

      @print(tick, 0, indent + "  ")

    if parent == null
      console.log ""

  getLineFromStack: (stack) ->
    stack = Error.prepareStackTrace(new Error("ohai"), stack)

    lines = stack.split("\n")
    for l in lines
      return l.replace(/^\s*/,'') if l.indexOf(process.cwd()) > -1 && l.indexOf('node_modules') < l.indexOf(process.cwd())

  diff: (after, before) ->
    @time([after[0] - before[0], after[1] - before[1]])

  time: (delta) ->
    ((1000 * delta[0]) + (delta[1] / 1000000)).toFixed(3)

  stop: () ->
    return if @end
    @end ||= process.hrtime()
    process.removeAsyncListener(@listener)
    @callback(@)

module.exports = AsyncProfile
