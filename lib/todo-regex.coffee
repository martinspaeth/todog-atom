module.exports =
class TodoRegex
  constructor: (issueNumber) ->
    @error = false
    @regexp = /\b(TODO)[:;.,]?\d*($|\s.*$|[\{\[\(].+$)/g
