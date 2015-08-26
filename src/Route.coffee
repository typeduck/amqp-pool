###############################################################################
# Represents a templated way to route data. The job of a Route instance is to
# convert templates into exchange/routing key
###############################################################################

flatten = require("lodash.flatten")
clone = require("lodash.clone")

Template = require("./Template")

# Used to determine Exchange+Route (as opposed to Queue)
rxExchangeRoute = /^([^\/]+)((?:\/[^\/]+)+)$/
# Used for finding all Routes after Exchange+Route match
rxRoute = /\/[^\/]+/g


module.exports = class Route
  # Can be instantiated with separate Exchange/Route, or slash-separated
  constructor: (exTpl, rkTpl = null) ->
    if not rkTpl?
      if rxExchangeRoute.test(exTpl)
        return Route.read(exTpl)[0]
      else
        rkTpl = exTpl
        exTpl = ""
    @tplEx = new Template(exTpl)
    @tplRk = new Template(rkTpl)
    @toString = () -> "#{exTpl}/#{rkTpl}"
  # Methods to determine the Exchange/Route
  exchange: (router) -> @tplEx.fill(router)
  route: (router) -> @tplRk.fill(router)
  # These methods exist because we do NOT want others accessing the template
  # instances directly, but Publisher/Consumer will still need them.
  # 
  # Methods to read the arbitrary options of the template pieces
  exchangeOptions: () -> clone(@tplEx.opts)
  routeOptions: () -> clone(@tplRk.opts)
  # Methos to read raw template source
  exchangeTemplate: () -> @tplEx.template
  routeTemplate: () -> @tplRk.template
  # Static method to read possible lots of routes
  @read: (args...) ->
    args = flatten(args)
    routes = []
    # Interpret the Exchange+Bindings
    bindings = args.map((s) -> rxExchangeRoute.exec(s)).filter((s) -> !!s)
    for spec in bindings
      for route in spec[2].match(rxRoute)
        routes.push(new Route(spec[1], route[1..]))
    # Straight-up Queue
    queues = args.filter (s) -> ! rxExchangeRoute.test(s)
    routes.push(new Route("", q)) for q in queues
    return routes
