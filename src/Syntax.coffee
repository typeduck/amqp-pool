###############################################################################
# Syntax for recognizing:
# - Exchange/Binding/Binding/... Specification
# - Queue Specification
# - Options for Exchange/Queue
# - Variable Replacement for templates
###############################################################################

# Used to determine Exchange+Route (as opposed to Queue)
exports.ExchangeRoute = /^([^\/]+)((?:\/[^\/]+)+)$/

# Used for finding all Routes after Exchange+Route match
exports.Route = /\/[^\/]+/g

# Used for single-letter flag options
exports.Options = /\?(\w*)(?:-(\w+))?/

# Used for variable replacement
exports.Template = /\{\{([^}]+)\}\}/g
