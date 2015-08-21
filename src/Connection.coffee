###############################################################################
# Our main class which manages:
# - one connection to AMQP server
# - pool of channels for publishing/consuming
# - list of named consumers (each consumer keeps dedicated channel)
# - list of named publishers (draw channels from the pool)
###############################################################################

_  = require("lodash")
async = require("async")
AMQP = require("amqplib/callback_api")
ChannelPool = require("./ChannelPool")
Publisher = require("./Publisher")
Consumer = require("./Consumer")

connectionId = 0

module.exports = class Connection
  constructor: (@specs = {}) ->
    @id = ++connectionId
    @conn = null
    getConn = () => @conn
    @poolConfirm = new ChannelPool(getConn, true)
    @poolNoConfirm = new ChannelPool(getConn, false)
    @url = @specs.server || "amqp://guest:guest@localhost"
    @publishers = {}
    @publish = {} # wrapper for named publisher's publish() method
    @consumers = {}
    for name, spec of (@specs.publishers || {})
      @addPublisher(name, spec)
    for name, spec of (@specs.consumers || {})
      @addConsumer(name, spec)
  # Adds a publisher template
  addPublisher: (name, spec) ->
    pub = (@publishers[name] ?= new Publisher(@poolNoConfirm, @poolConfirm, spec))
    @publish[name] ?= (args...) => pub.publish.apply(pub, args)
    return pub
  # Adds a consumer method
  addConsumer: (name, spec) ->
    con = (@consumers[name] = new Consumer(@poolNoConfirm, spec))
  # Connects, sets up listener in case of disconnect
  #connect: (cb) ->
  #  AMQP.connect @url, (err, conn) =>
  #    return cb(err) if err
  #    (@conn = conn).on "close"
      
  # sets up consumers/publishers
  activate: (cb) ->
    async.auto {
      connection: (next, auto) => AMQP.connect(@url, next)
      consumers: ["connection", (next, auto) =>
        @conn = auto.connection
        startConsumer = (name, done) => @consumers[name].activate(done)
        async.map(Object.keys(@consumers), startConsumer, next)
      ]
    }, (err, res) => cb?.call?(@, err, res)
    return @
  # Deactivates Consumers, Publishers, then connection
  deactivate:  (cb) ->
    console.log("Deactivating Connection %s", @id)
    async.auto {
      consumers: (next, auto) =>
        stopConsumer = (name, done) => @consumers[name].deactivate(done)
        async.map(Object.keys(@consumers), stopConsumer, next)
      poolNoConfirm: ["consumers", (next, auto) =>
        @poolNoConfirm.drain () =>
          @poolNoConfirm.destroyAllNow()
          next()
      ]
      poolConfirm: (next, auto) =>
        @poolConfirm.drain () =>
          @poolConfirm.destroyAllNow()
          next()
      connection: ["poolNoConfirm", "poolConfirm", (next, auto) =>
        @conn.on "close", () -> next()
        @conn.close()
        @conn = null
      ]
    }, (err, res) => cb?.call?(@, err, res)
    return @


# Exchange Options
rxExchangeOpt = /(-)?([adcnp])/g
exchangeMap =
  a: "autoDelete"
  d: "durable"
  c: "confirm"
  n: "noDeclare"
  p: "passive"
setExchangeOptions = (s) ->
  return {} if not s
  opts = {}
  while (m = rxExchangeOpt.exec(s))
    opts[exchangeMap[m[2]]] = ! m[1]
  return opts

# Publishing Options
rxPubOpt = /(-)?([mip])/g
pubMap =
  m: "mandatory"
  i: "immediate"
setPublishOptions = (s) ->
  return {} if not s
  opts = {}
  while (m = rxPubOpt.exec(s))
    if m[2] is "p"
      opts.deliveryMode = if m[1] then 1 else 2
    else
      opts[pubMap[m[2]]] = ! m[1]
  return opts
