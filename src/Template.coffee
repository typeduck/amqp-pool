###############################################################################
# Variable Lookup template
###############################################################################

_ = require("lodash")
Mustache = require("mustache")
Syntax = require("./Syntax")

module.exports = class Template
  constructor: (@template, @opts = {}) ->
    if opts = @template.match(Syntax.Options)
      @template = @template.replace(opts[0], "")
      if (letters = opts[1])
        @opts[k] ?= true for k in letters.split("")
      if (letters = opts[2])
        @opts[k] ?= false for k in letters.split("")
  # Fills in the template using the list of sources provided
  fill: (view) ->
    filled = Mustache.render(@template, view)
    if @opts.trimDots
      return filled.replace(/\.{2,}/g, ".").replace(/^\.|\.$/g, "")
    else
      return filled
