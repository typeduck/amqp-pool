###############################################################################
# Given a channel pool, publishes messages using templates
###############################################################################

When = require("when")
Route = require("./Route")

publisherId = 0

module.exports = class Publisher
  constructor: (@uncertain, @certain, @spec) ->
    @id = ++publisherId
    @route = null
    @messageId = 0
    if typeof @spec is "string" then @spec = {route: @spec}
    @setRoute(@spec.route)
  # Sets the publishing route
  setRoute: (tpl) -> @route = Route.read(tpl)[0]
  # Publishes a message along all the routes
  publish: (message, args...) ->
    done = null
    messageId = ++@messageId
    isConfirm = false
    # by default use the message itself to create routing key
    tplData = message
    for arg in args when arg?
      if typeof arg is "boolean" then isConfirm = arg
      if typeof arg is "object" then tplData = arg
    # Prepare the message
    exchange = @route.exchange(tplData)
    rKey = @route.route(tplData)
    content = new Buffer(JSON.stringify(message), "utf8")
    pOpts =
      contentType: "application/json"
      contentEncoding: "UTF-8"
    # Acquire the channel and publish message
    pool = if isConfirm then @certain else @uncertain
    pool.acquire().then((channel) ->
      # Non-Confirm mode: immediately release the Channel
      if not isConfirm
        channel.publish(exchange, rKey, content, pOpts)
        return pool.release(channel)
      # Confirm Mode: setup error handler/ACK handler. Seems that
      # amqplib.ConfirmChannel.publish is NOT Promise-based.
      When.promise((resolve, reject) ->
        onDone = (err, ok) ->
          channel.removeListener("error", onDone)
          pool.release(channel)
          if err then reject(err) else resolve(ok)
        channel.publish(exchange, rKey, content, pOpts, onDone)
        channel.on("error", onDone)
      )
    )
