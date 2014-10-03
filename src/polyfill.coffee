require 'async-listener'
wrapCallback = require 'async-listener/glue'

module.exports = () -> # extends AsyncListener
  @wrap = (fn) ->
    wrapCallback(fn)

  @bridge = (fn) ->
    () ->
      index = arguments.length - 1
      if typeof arguments[index] == "function"
        arguments[index] = wrapCallback(arguments[index])
      fn.apply(this, arguments)

  @bridgeRedisPackage = (redis) ->
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

  @bridgeMongoDb = (db) ->
    db._executeInsertCommand = AsyncProfile.bridge(db._executeInsertCommand)
    db._executeQueryCommand  = AsyncProfile.bridge(db._executeQueryCommand)
    db._executeUpdateCommand = AsyncProfile.bridge(db._executeUpdateCommand)
    db._executeRemoveCommand = AsyncProfile.bridge(db._executeRemoveCommand)

