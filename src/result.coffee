
class Result

  constructor: (profile) ->

    @ticks = profile.ticks
    @start = profile.start
    @end = profile.end

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

    "total: #{@time(sum)}ms (in #{@diff(max, min)}ms real time, CPU load: #{(@time(sum) / @diff(max, min)).toFixed(1)}, wait time: #{@time(wait)}ms)"

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
    if Error.prepareStackTrace
      stack = Error.prepareStackTrace(new Error("ohai"), stack)
    else
      stack = "new Error('ohai')\n" +
        stack.map((f) -> " at #{f.toString()}\n").join("")

    lines = stack.split("\n")
    for l in lines
      return l.replace(/^\s*/,'') if l.indexOf(process.cwd()) > -1 && l.indexOf('node_modules') < l.indexOf(process.cwd())

    for l in lines
      return l.replace(/^\s*/,'') if l.indexOf(process.cwd()) > -1 &&  l.indexOf('async-profile') == -1

    for l in lines.slice(1)
      return l.replace(/^\s*/,'') if l.indexOf('async-profile') == -1

  diff: (after, before) ->
    @time([after[0] - before[0], after[1] - before[1]])

  time: (delta) ->
    ((1000 * delta[0]) + (delta[1] / 1000000)).toFixed(3)

  stop: () ->
    return if @end
    @end ||= process.hrtime()
    process.removeAsyncListener(@listener)
    @opts.callback(@)

module.exports = Result
