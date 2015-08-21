###############################################################################
# Represents a templated way to route data. The job of a Route instance is to
# convert templates into exchange/routing key
###############################################################################

_ = require("lodash")

Template = require("./Template")
Syntax = require("./Syntax")

module.exports = class Route
  # Can be instantiated with separate Exchange/Route, or slash-separated
  constructor: (exTpl, rkTpl = null) ->
    if not rkTpl?
      if Syntax.ExchangeRoute.test(exTpl)
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
  exchangeOptions: () -> _.clone(@tplEx.opts)
  routeOptions: () -> _.clone(@tplRk.opts)
  # Methos to read raw template source
  exchangeTemplate: () -> @tplEx.template
  routeTemplate: () -> @tplRk.template
  # Static method to read possible lots of routes
  @read: (args...) ->
    args = _.flatten(args)
    routes = []
    # Interpret the Exchange+Bindings
    bindings = args.map((s) -> Syntax.ExchangeRoute.exec(s)).filter((s) -> !!s)
    for spec in bindings
      for route in spec[2].match(Syntax.Route)
        routes.push(new Route(spec[1], route[1..]))
    # Straight-up Queue
    queues = args.filter (s) -> ! Syntax.ExchangeRoute.test(s)
    routes.push(new Route("", q)) for q in queues
    return routes
