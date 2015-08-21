###############################################################################
# Main file, only supports making a new Connection
###############################################################################

Connection = require("./Connection")

module.exports = (specs) -> return new Connection(specs)
