###############################################################################
# Small Wrapper around generic pool to create AMQP Channels, with/without
# confirms
###############################################################################

_ = require("lodash")
Pools = require("generic-pool")

idPool = 0

module.exports = class ChannelPool
  constructor: (getConn, confirm, opts = {}) ->
    fName = "create" + (if confirm then "Confirm" else "") + "Channel"
    name = "amqp-channels-" + (if confirm then "" else "no") + "confirm"
    name += "-" + (++idPool)
    @pool = pool = Pools.Pool(_.assign({
      name: name
      create: (callback) ->
        if not (connection = getConn())
          return callback(new Error("Could not get connection"))
        # Channel initialization, add valid/close stuff
        connection[fName] (err, channel) ->
          return callback(err) if err
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
      validate: (channel) -> channel.isValid
      destroy: (channel) -> channel.close() if not channel.isClosed
      min: 0
      max: 20
      idleTimeoutMillis: 30000
    }, _.pick(opts, "min", "max", "idleTimeoutMillis", "name")))
  # Wrapper for pool.acquire/pool.release
  acquire: (next) -> @pool.acquire(next)
  release: (channel) -> @pool.release(channel)
  drain: (cb) -> @pool.drain(cb)
  destroyAllNow: () -> @pool.destroyAllNow()
