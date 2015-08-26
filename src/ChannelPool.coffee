###############################################################################
# Small Wrapper around generic pool to create AMQP Channels, with/without
# confirms
###############################################################################

When = require("when")
assign = require("lodash.assign")
pick = require("lodash.pick")
Pools = require("generic-pool")

idPool = 0

module.exports = class ChannelPool
  constructor: (@connection, @options = {}) ->
    @id = (++idPool)
    fnCreate = "createChannel"
    @name = "amqp-channels-no-confirm"
    if @options.confirm
      fnCreate = "createConfirmChannel"
      @name = "amqp-channels-confirm"
    else
      fnCreate = "createChannel"
      @name = "amqp-channels-no-confirm"
    @name += "-" + @id
    @pool = pool = Pools.Pool(assign({
      name: @name
      create: (callback) =>
        @connection.connect().then((conn) ->
          conn[fnCreate]()
        ).then((channel) ->
          # Error Detection for validation
          ctErrors = 0
          Object.defineProperty(channel, "isValid", {get: -> ! ctErrors })
          channel.on "error", (e) -> ctErrors += 1
          # Closed detection to not double-close
          isClosed = false
          Object.defineProperty(channel, "isClosed", {get: -> isClosed})
          channel.on "close", () -> isClosed = true
          # Return the Channel
          callback(null, channel)
        ).catch(callback)
      validate: (channel) -> channel.isValid
      destroy: (channel) -> channel.close() if not channel.isClosed
      min: 0
      max: 20
      idleTimeoutMillis: 30000
    }, pick(@options, "min", "max", "idleTimeoutMillis", "name")))
  # Wrapper for pool.acquire/pool.release
  acquire: () ->
    When.promise((resolve, reject) =>
      @pool.acquire((err, channel) ->
        if err then reject(err) else resolve(channel)
      )
    )
  release: (channel) -> @pool.release(channel)
  drain: () ->
    When.promise (resolve, reject) =>
      @pool.destroyAllNow()
      resolve()
