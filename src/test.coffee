###############################################################################
# Tests out our local server
###############################################################################

should = require("should")
pool = require("./index")
AMQP = require("amqplib/callback_api")
async = require("async")
_ = require("lodash")

# HELPER METHODS FOR before/after test suite
setupLife = (setup) ->
  return (done) ->
    async.auto {
      conn: (next, auto) ->
        AMQP.connect(next)
      channel: ["conn", (next, auto) ->
        auto.conn.createConfirmChannel(next)
      ]
      animalia: ["channel", (next, auto) ->
        auto.channel.assertExchange("Animalia", "topic", {}, next)
      ]
      plantae: ["channel", (next, auto) ->
        auto.channel.assertExchange("Plantae", "topic", {}, next)
      ]
    }, (err, res) -> done(err, _.assign(setup, res))
removeLife = (setup) ->
  return (done) ->
    return done() if not setup
    async.series [
      (next) -> setup.channel.deleteExchange("Animalia", {}, next)
      (next) -> setup.channel.deleteExchange("Plantae", {}, next)
      (next) -> setup.channel.close(next)
      (next) -> setup.conn.close(next)
    ], done

###############################################################################
# Tests that we can make a connection
###############################################################################
describe "Connection", () ->
  # Set the conditions for life on our AMQP server
  before(setupLife(setup = {}))
  # Remove expected exchanges
  after(removeLife(setup))
  # Creates another (default) connection
  it "should be able to create default connection", (done) ->
    pool().activate () -> @deactivate(done)
  # Creates explicit connection
  it "should be able to accept server URL", (done) ->
    pool({server: "amqp://guest:guest@localhost"}).activate () ->
      @deactivate(done)

# Tests only the route templating
describe "Route [internal]", () ->
  Route = require("./Route")
  # Stupid test object
  obj =
    a: {b: "Hello"}
    c: "World"
    d: {e: "I", h: "NO", i: "NO"}
    f: "here"
    g: {h: {i: "now"}}
  it "should handle direct to queue", () ->
    obj = {}
    route = new Route("direct-to-queue")
    route.exchange(obj).should.equal("")
    route.route(obj).should.equal("direct-to-queue")

  it "should handle basic templating", () ->
    obj =
      a: {b: "Hello"}
      c: "World"
      d: {e: "I"}
      f: "here"
    route = new Route("{{a.b}}-{{c}}/{{d.e}}.is.{{f}}")
    route.exchange(obj).should.equal("Hello-World")
    route.route(obj).should.equal("I.is.here")
    
    route = new Route("{{a.b}}-{{c}}", "{{d.e}}.is.{{f}}")
    route.exchange(obj).should.equal("Hello-World")
    route.route(obj).should.equal("I.is.here")

  it "should create Queue-based routing", () ->
    routes = Route.read("direct-to-queue")
    routes[0].exchange(obj).should.equal("")
    routes[0].route(obj).should.equal("direct-to-queue")

  it "should create Queue-based routing (with arbitrary options)", () ->
    routes = Route.read("direct-to-queue?edc-p")
    routes[0].exchange(obj).should.equal("")
    routes[0].route(obj).should.equal("direct-to-queue")

  it "should read routes in a few ways", () ->
    obj =
      ex1: "Animalia"
      rk1: "Chordata"
      rk2: "Echinodermata"
      ex2: "Plantae"
      rk3: "Magnoliophyta"
      rk4: "Chlorophyta"
    # First way: as array
    routes = Route.read(["{{ex1}}?d/{{rk1}}?c/{{rk2}}?c", "{{ex2}}/{{rk3}}/{{rk4}}"])
    routes.length.should.equal(4)
    routes[0].exchange(obj).should.equal("Animalia")
    routes[0].route(obj).should.equal("Chordata")
    routes[1].exchange(obj).should.equal("Animalia")
    routes[1].route(obj).should.equal("Echinodermata")
    routes[2].exchange(obj).should.equal("Plantae")
    routes[2].route(obj).should.equal("Magnoliophyta")
    routes[3].exchange(obj).should.equal("Plantae")
    routes[3].route(obj).should.equal("Chlorophyta")
    # Second way: as arguments
    routes = Route.read("{{ex1}}/{{rk1}}/{{rk2}}", "{{ex2}}/{{rk3}}/{{rk4}}")
    routes.length.should.equal(4)
    routes[0].exchange(obj).should.equal("Animalia")
    routes[0].route(obj).should.equal("Chordata")
    routes[1].exchange(obj).should.equal("Animalia")
    routes[1].route(obj).should.equal("Echinodermata")
    routes[2].exchange(obj).should.equal("Plantae")
    routes[2].route(obj).should.equal("Magnoliophyta")
    routes[3].exchange(obj).should.equal("Plantae")
    routes[3].route(obj).should.equal("Chlorophyta")
    # Third way: arguments including array
    routes = Route.read("{{ex1}}/{{rk1}}/{{rk2}}", ["{{ex2}}/{{rk3}}/{{rk4}}"])
    routes.length.should.equal(4)
    routes[0].exchange(obj).should.equal("Animalia")
    routes[0].route(obj).should.equal("Chordata")
    routes[1].exchange(obj).should.equal("Animalia")
    routes[1].route(obj).should.equal("Echinodermata")
    routes[2].exchange(obj).should.equal("Plantae")
    routes[2].route(obj).should.equal("Magnoliophyta")
    routes[3].exchange(obj).should.equal("Plantae")
    routes[3].route(obj).should.equal("Chlorophyta")

# Publish/Consume
describe "Publisher", ()  ->
  # Make sure that proper setup is acheived
  before(setupLife(setup = {}))
  after(removeLife(setup))
  
  # Tests 500 messages
  it "should be able to set up publisher/consumer", (done) ->
    @timeout(5000)
    maxHumans = 1000
    countDown = (maxHumans + 1) * (maxHumans / 2) * 3
    gotMessage = (msg) ->
      o = msg.json
      o.kingdom.should.equal("Animalia")
      o.phylum.should.equal("Chordata")
      o["class"].should.equal("Mammalia")
      o.order.should.equal("Primates")
      o.family.should.equal("Hominadae")
      o.genus.should.equal("Homo")
      o.species.should.equal("sapiens")
      countDown -= msg.json.id
      if countDown is 0 then P.deactivate(done)
    P = pool({
      maxChannels: 8
      publishers:
        life: "{{kingdom}}/{{phylum}}.{{class}}.{{order}}.{{family}}.{{genus}}.{{species}}"
      consumers:
        apes:
          routes: ["Animalia/Chordata.*.Primates.#"]
          method: gotMessage
        humans:
          routes: ["Animalia/#.sapiens"]
          method: gotMessage
        generic:
          routes: "Animalia/#"
          method: gotMessage
    })
    P.activate (err, res) ->
      # publish a bunch of humans ;-)
      for i in [1..maxHumans]
        @publish.life({
          kingdom: "Animalia"
          phylum: "Chordata"
          class: "Mammalia"
          order: "Primates"
          family: "Hominadae"
          genus: "Homo"
          species: "sapiens"
          id: i
        })

  # Test that publishing one bad route does not corrupt another
  it "should multi-route publisher must continue in face of errors",  (done) ->
    maxAnimals = 2
    countDown = (maxAnimals + 1) * (maxAnimals / 2)
    gotMessage = (msg) ->
      o = msg.json
      o.kingdom.should.equal("Animalia")
      countDown -= msg.json.id
      if countDown is 0 then P.deactivate(done)
    P = pool({
      publishers:
        life: "{{kingdom}}/{{phylum}}.{{class}}.{{order}}.{{family}}.{{genus}}.{{species}}"
        bad: "Non-Existent/{{phylum}}.{{class}}.{{order}}.{{family}}.{{genus}}.{{species}}"
      consumers:
        living:
          routes: "Animalia/#"
          method: gotMessage
    }).activate (err) ->
      return done(err) if err
      for i in [1..maxAnimals]
        @publish.life({
          kingdom: "Animalia"
          phylum: "Chordata"
          class: "Mammalia"
          order: "Primates"
          family: "Hominadae"
          genus: "Homo"
          species: "sapiens"
          id: i
        }, ((e) -> return done(e) if e) )
        @publish.bad({
          kingdom: "Animalia"
          phylum: "Chordata"
          class: "Mammalia"
          order: "Primates"
          family: "Hominadae"
          genus: "Homo"
          species: "sapiens"
          id: i
        })
