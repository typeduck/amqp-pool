###############################################################################
# Wrapper for consuming messages
###############################################################################

When = require("when")
Route = require("./Route")

# Used for variable replacement
rxTemplate = /\{\{([^}]+)\}\}/g

consumerId = 0

module.exports = class Consumer
  constructor: (@pool, @spec) ->
    @id = ++consumerId
    @channel = null
    @dynamicQueue = null
    @routes = Route.read(@spec.routes)
    @subscriptions = []
  # Creates a dynamic queue (if not existing), and always subscribes to it
  dynamic: () ->
    @connect().then((ch) =>
      qOpts = {exclusive: true, durable: false, autoDelete: true}
      # Always subscribe to our callback handler, even before binding
      @dynamicQueue ?= ch.assertQueue("", qOpts)
      @dynamicQueue.then((ok) =>
        sOpts = {noAck: true}
        ch.consume(ok.queue, @callMethod.bind(@, ch), sOpts)
      ).then((sub) =>
        @subscriptions.push(sub)
      )
      return @dynamicQueue
    )
  connect: () -> @channel ?= @pool.acquire()
  # Acquires a channel for consumption and keeps until deactivated
  activate: () -> When.all((@addRoute(route) for route in @routes))
  # Adds a Route (either Queue or Exchange/Binding to dynamic Queue)
  addRoute:  (route) ->
    @connect().then((ch) =>
      # TODO: Consumer routes should not allow templates!
      exchange = route.exchangeTemplate()
      route = route.routeTemplate()
      if rxTemplate.test(route)
        throw new Error("Invalid consumption route '#{route}'")
      # Queue: subscribe directly to it
      if not exchange
        return ch.consume(route, @callMethod.bind(@, ch)).then((sub) =>
          @subscriptions.push(sub)
        )
      # It is an exchange, create/bind Queue
      if rxTemplate.test(exchange)
        throw new Error("Invalid Exchange '#{exchange}'")
      return @dynamic().then((ok) ->
        ch.bindQueue(ok.queue, exchange, route)
      )
    )

  # Wrapper for the method call
  callMethod: (ch, msg) ->
    return if not (props = msg?.properties) or not (fields = msg.fields)
    try
      if props.contentType is "application/json"
        msg.json = JSON.parse(msg.content.toString(msg.contentEncoding || "UTF-8"))
      @spec.method.call(@, msg)
    catch e
      console.error(e, e.stack)
  # Wrappper for the acknowlegement
  ack: (msg) ->
    @connect().then((ch) ->
      ch.acknowledge(msg)
    )

  # Stop consuming, shutdown, release
  deactivate: () ->
    @connect().then((ch) =>
      all = (ch.cancel(sub.consumerTag) for sub in @subscriptions)
      When.all(all).then(() =>
        @subscriptions = []
        @pool.release(ch)
        @channel = null
      )
    )
