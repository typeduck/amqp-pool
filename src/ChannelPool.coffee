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
  constructor: (connect, confirm, opts = {}) ->
    fnCreate = "create" + (if confirm then "Confirm" else "") + "Channel"
    name = "amqp-channels-" + (if confirm then "" else "no") + "confirm"
    name += "-" + (++idPool)
    @pool = pool = Pools.Pool(assign({
      name: name
      create: (callback) ->
        connect().then((conn) ->
          conn[fnCreate]().then((channel) ->
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
          )
        ).catch(callback)
      validate: (channel) -> channel.isValid
      destroy: (channel) -> channel.close() if not channel.isClosed
      min: 0
      max: 20
      idleTimeoutMillis: 30000
    }, pick(opts, "min", "max", "idleTimeoutMillis", "name")))
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
