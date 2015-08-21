###############################################################################
# Wrapper for consuming messages
###############################################################################

async = require("async")
Syntax = require("./Syntax")
Route = require("./Route")

consumerId = 0

module.exports = class Consumer
  constructor: (@pool, @spec) ->
    @id = ++consumerId
    @channel = null
    @dynamicQueue = null
    @routes = Route.read(@spec.routes)
    @subscriptions = []
  # Creates a dynamic queue (if not existing), and always subscribes to it
  dynamic: (done) ->
    if not @channel then return done(new Error("Channel not ready"))
    if @dynamicQueue then return done(null, @dynamicQueue)
    qOpts = {exclusive: true, durable: false, autoDelete: true}
    # Always subscribe to our callback handler, even before binding
    @channel.assertQueue "", qOpts, (err, ok) =>
      return done(err) if err
      @dynamicQueue = ok
      sOpts = {noAck: true}
      @channel.consume(ok.queue, @callMethod.bind(@), sOpts, @consumed(done))
  # Acquires a channel for consumption and keeps until deactivated
  activate: (cb) ->
    if @channel then return cb()
    @pool.acquire (err, channel) =>
      return cb(err) if err
      @channel = channel
      #console.log("Connection %s; Consumer %s; got Channel %s", @pool.connectionId, @id, @channel.ch)
      async.map(@routes, @addRoute.bind(@), cb)
  # Adds a Route (either Queue or Exchange/Binding to dynamic Queue)
  addRoute:  (route, done) ->
    if not @channel then return done(new Error("Channel not ready"))
    # TODO: Consumer routes should not allow templates!
    exchange = route.exchangeTemplate()
    route = route.routeTemplate()
    if Syntax.Template.test(route)
      return done(new Error("Invalid consumption route '#{route}'"))
    # Queue: subscribe directly to it
    if not exchange
      @channel.consume(route, @callMethod.bind(@), {}, @consumed(done))
    # It is an exchange, create/bind Queue
    else
      if Syntax.Template.test(exchange)
        return done(new Error("Invalid Exchange '#{exchange}'"))
      @dynamic (err, ok) =>
        @channel.bindQueue(ok.queue, exchange, route, {}, done)
  # Keeps track of our consumer tags for later deactivation
  consumed: (cb) ->
    return (err, ok) =>
      #console.log("Connection %s; Consumer %s; Channel %s, cTag %s", @pool.connectionId, @id, @channel.ch, ok.consumerTag)
      @subscriptions.push(ok) if ok?
      cb(err, ok)

  # Wrapper for the method call
  callMethod: (msg) ->
    return if not (props = msg?.properties) or not (fields = msg.fields)
    #console.log("Connection %s; Consumer %s; Channel %s, cTag %s; delivery %s", @pool.connectionId, @id, @channel.ch, fields.consumerTag, fields.deliveryTag)
    try
      if props.contentType is "application/json"
        msg.json = JSON.parse(msg.content.toString(msg.contentEncoding || "UTF-8"))
      @spec.method.call(@, msg)
    catch e
      console.error(e, e.stack)
  # Wrappper for the acknowlegement
  ack: (msg) ->
    @channel.acknowledge(msg)

  # Stop consuming, shutdown, release
  deactivate: (cb) ->
    cancel = (sub, next) =>
      #console.log("Connection %s; Consumer %s; Channel %s; cancel('%s')", @pool.connectionId, @id, @channel.ch, sub.consumerTag)
      @channel.cancel(sub.consumerTag, next)
    async.map @subscriptions, cancel, (err) =>
      @subscriptions = []
      #console.log("Connection %s; Consumer %s; Channel %s; released", @pool.connectionId, @id, @channel.ch)
      @pool.release(@channel)
      @channel = null
      cb(err)
