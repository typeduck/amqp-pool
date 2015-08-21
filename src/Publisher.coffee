###############################################################################
# Given a channel pool, publishes messages using templates
###############################################################################

async = require("async")
Route = require("./Route")

publisherId = 0

module.exports = class Publisher
  constructor: (@uncertain, @certain, @spec) ->
    @id = ++publisherId
    @messageId = 0
    @route = null
    if typeof @spec is "string" then @spec = {route: @spec}
    @setRoute(@spec.route)
  # Sets the publishing route
  setRoute: (tpl) -> @route = Route.read(tpl)[0]
  # Publishes a message along all the routes
  publish: (message, args...) ->
    done = null
    messageId = ++@messageId
    tplData = null
    for arg in args when arg?
      if typeof arg is "function" then done = arg
      if typeof arg is "object" then tplData = arg
    # by default use the message itself to create routing key
    tplData ?= message
    # Determine the type of pool needed
    isConfirm = typeof done is "function"
    pool = if isConfirm then @certain else @uncertain
    # Acquire the channel and publish message
    pool.acquire (err, channel) =>
      return done?(err) if err
      # Prepare the message
      exchange = @route.exchange(tplData)
      rKey = @route.route(tplData)
      content = new Buffer(JSON.stringify(message), "utf8")
      pOpts =
        contentType: "application/json"
        contentEncoding: "UTF-8"
      # Non-Confirm mode: immediately release the Channel
      if not isConfirm
        channel.publish(exchange, rKey, content, pOpts)
        return pool.release(channel)
      # Confirm Mode: setup error handler/ACK handler
      onDone = (err, results) =>
        channel.removeListener("error", onDone)
        pool.release(channel)
        done?(err, results)
      channel.on("error", onDone)
      channel.publish(exchange, rKey, content, pOpts, onDone)
