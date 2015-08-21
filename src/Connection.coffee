###############################################################################
# Our main class which manages:
# - one connection to AMQP server
# - pool of channels for publishing/consuming
# - list of named consumers (each consumer keeps dedicated channel)
# - list of named publishers (draw channels from the pool)
###############################################################################

When = require("when")
AMQP = require("amqplib")
ChannelPool = require("./ChannelPool")
Publisher = require("./Publisher")
Consumer = require("./Consumer")

connectionId = 0

module.exports = class Connection
  constructor: (@specs = {}) ->
    @id = ++connectionId
    @url = @specs.server || "amqp://guest:guest@localhost"
    @conn = null
    getConn = () => @connect()
    @poolConfirm = new ChannelPool(getConn, true)
    @poolNoConfirm = new ChannelPool(getConn, false)
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
  connect: () -> @conn ?= AMQP.connect(@url)
  disconnect: () ->
    @conn?.then((c) =>
      @conn = null
      c.close()
    )
  # sets up consumers/publishers
  activate: () -> When.all((con.activate() for name, con of @consumers))
  # Deactivates Consumers, Publishers, then connection
  deactivate:  () ->
    console.log("Deactivating Connection %s", @id)
    all = (con.deactivate() for name, con of @consumers)
    all.push(@poolConfirm.drain())
    When.all(all).then(() =>
      @poolNoConfirm.drain()
    ).then(() => @disconnect())

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
