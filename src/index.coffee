###############################################################################
# Main file, only supports making a new Connection
###############################################################################

Connection = require("./Connection")

module.exports = (specs) -> new Connection(specs)

module.exports.ChannelPool = require("./ChannelPool")
module.exports.Publisher = require("./Publisher")
module.exports.Consumer = require("./Consumer")
