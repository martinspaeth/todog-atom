path = require 'path'
{Emitter} = require 'atom'

TodoModel = require './todo-model'
TodosMarkdown = require './todo-markdown'
TodoRegex = require './todo-regex'

module.exports =
class TodoCollection
  constructor: ->
    @emitter = new Emitter
    @defaultKey = 'Text'
    @scope = 'workspace'
    @issueNumber = null
    @todos = []

  onDidAddTodo: (cb) -> @emitter.on 'did-add-todo', cb
  onDidRemoveTodo: (cb) -> @emitter.on 'did-remove-todo', cb
  onDidClear: (cb) -> @emitter.on 'did-clear-todos', cb
  onDidStartSearch: (cb) -> @emitter.on 'did-start-search', cb
  onDidSearchPaths: (cb) -> @emitter.on 'did-search-paths', cb
  onDidFinishSearch: (cb) -> @emitter.on 'did-finish-search', cb
  onDidCancelSearch: (cb) -> @emitter.on 'did-cancel-search', cb
  onDidFailSearch: (cb) -> @emitter.on 'did-fail-search', cb
  onDidSortTodos: (cb) -> @emitter.on 'did-sort-todos', cb
  onDidFilterTodos: (cb) -> @emitter.on 'did-filter-todos', cb
  onDidChangeSearchScope: (cb) -> @emitter.on 'did-change-scope', cb
  onDidChangeIssueNumber: (cb) -> @emitter.on 'did-change-issue-number', cb


  clear: ->
    @cancelSearch()
    @todos = []
    @emitter.emit 'did-clear-todos'

  addTodo: (todo) ->
    return if @alreadyExists(todo)
    @todos.push(todo)
    @emitter.emit 'did-add-todo', todo

  getTodos: -> @todos
  getTodosCount: -> @todos.length
  getState: -> @searching

  sortTodos: ({sortBy, sortAsc} = {}) ->
    sortBy ?= @defaultKey

    # Save history of new sort elements
    if @searches?[@searches.length - 1].sortBy isnt sortBy
      @searches ?= []
      @searches.push {sortBy, sortAsc}
    else
      @searches[@searches.length - 1] = {sortBy, sortAsc}

    @todos = @todos.sort((todoA, todoB) =>
      @todoSorter(todoA, todoB, sortBy, sortAsc)
    )

    return @filterTodos(@filter)
    @emitter.emit 'did-sort-todos', @todos

  todoSorter: (todoA, todoB, sortBy, sortAsc) ->
    [sortBy2, sortAsc2] = [sortBy, sortAsc]

    aVal = todoA.get(sortBy2)
    bVal = todoB.get(sortBy2)

    if aVal is bVal
      # Use previous sorts to make a 2-level stable sort
      if search = @searches?[@searches.length - 2]
        [sortBy2, sortAsc2] = [search.sortBy, search.sortAsc]
      else
        sortBy2 = @defaultKey

      [aVal, bVal] = [todoA.get(sortBy2), todoB.get(sortBy2)]

    # Sort type in the defined order, as number or normal string sort
    if sortBy2 is 'Type'
      findTheseTodos = atom.config.get('todog-atom.findTheseTodos')
      comp = findTheseTodos.indexOf(aVal) - findTheseTodos.indexOf(bVal)
    else if todoA.keyIsNumber(sortBy2)
      comp = parseInt(aVal) - parseInt(bVal)
    else
      comp = aVal.localeCompare(bVal)
    if sortAsc2 then comp else -comp

  filterTodos: (filter) ->
    @filter = filter
    @emitter.emit 'did-filter-todos', @getFilteredTodos()

  getFilteredTodos: ->
    filter = @filter
    issueNumber = @issueNumber

    @todos.filter (todo) ->

      filterMatch = true
      if filter
        filterMatch = todo.contains(filter)

      issueMatch = false
      if issueNumber
        issueMatch = (todo.issue == "##{issueNumber}")
      else
        issueMatch = true


      # todo has no issue number include it
      if !todo.issue?
        issueMatch = true

      return (filterMatch && issueMatch)


  getAvailableTableItems: -> @availableItems
  setAvailableTableItems: (@availableItems) ->

  getSearchScope: -> @scope
  setSearchScope: (scope) ->
    @emitter.emit 'did-change-scope', @scope = scope

  toggleSearchScope: ->
    scope = switch @scope
      when 'workspace' then 'project'
      when 'project' then 'open'
      when 'open' then 'active'
      else 'workspace'
    @setSearchScope(scope)
    scope

  getIssueNumber: -> @issueNumber
  setIssueNumber: (issueNumber) ->
    console.log('setIssueNumber')
    if issueNumber != @issueNumber
      @emitter.emit 'did-change-issue-number', @issueNumber = issueNumber

  toggleIssueScope: ->
    issueNumberScopeActive = false
    if !@issueNumber?
      issueNumberScopeActive = true

    issueNumber = null
    if issueNumberScopeActive
      issueNumber = @getCurrentBranchIssueNumber()

    @setIssueNumber(issueNumber)
    issueNumber


  getCustomPath: -> @customPath
  setCustomPath: (@customPath) ->

  alreadyExists: (newTodo) ->
    properties = ['range', 'path']
    @todos.some (todo) ->
      properties.every (prop) ->
        true if todo[prop] is newTodo[prop]

  # Scan project workspace for the TodoRegex object
  # returns a promise that the scan generates
  fetchRegexItem: (todoRegex, activeProjectOnly) ->
    options =
      paths: @getSearchPaths()
      onPathsSearched: (nPaths) =>
        @emitter.emit 'did-search-paths', nPaths if @searching

    atom.workspace.scan todoRegex.regexp, options, (result, error) =>
      console.debug error.message if error
      return unless result

      return if activeProjectOnly and not @activeProjectHas(result.filePath)

      for match in result.matches
        @addTodo new TodoModel(
          all: match.lineText
          text: match.matchText
          loc: result.filePath
          position: match.range
          regex: todoRegex.regex
          regexp: todoRegex.regexp
        )

  # Scan open files for the TodoRegex object
  fetchOpenRegexItem: (todoRegex, activeEditorOnly) ->
    editors = []
    if activeEditorOnly
      if editor = atom.workspace.getActiveTextEditor()
        editors = [editor]
    else
      editors = atom.workspace.getTextEditors()

    for editor in editors
      editor.scan todoRegex.regexp, (match, error) =>
        console.debug error.message if error
        return unless match

        range = [
          [match.range.start.row, match.range.start.column]
          [match.range.end.row, match.range.end.column]
        ]

        @addTodo new TodoModel(
          all: match.lineText
          text: match.matchText
          loc: editor.getPath()
          position: range
          regex: todoRegex.regex
          regexp: todoRegex.regexp
        )

    # No async operations, so just return a resolved promise
    Promise.resolve()

  getCurrentBranchIssueNumber: ->
    branchName = atom.project.getRepositories()[0].getShortHead()
    issueNumber = null
    branchNameParts = branchName.split('-')
    if branchNameParts.length > 0
      if /^\d+$/.test(branchNameParts[0])
        issueNumber = branchNameParts[0]
    return issueNumber

  search: (force = false) ->
    return if !atom.config.get('todog-atom.autoRefresh') and !force

    if @issueNumber
      console.log('issue number')
      # with every search also check the branch
      issueNumber = @getCurrentBranchIssueNumber()
      if issueNumber != @issueNumber
        console.log('issue number after calling search')
        @setIssueNumber(issueNumber)
        return
      console.log('issue number did not change')


    @clear()
    @searching = true
    @emitter.emit 'did-start-search'

    todoRegex = new TodoRegex(@issueNumber)

    if todoRegex.error
      @emitter.emit 'did-fail-search', "Invalid todo search regex"
      return

    @searchPromise = switch @scope
      when 'open' then @fetchOpenRegexItem(todoRegex, false)
      when 'active' then @fetchOpenRegexItem(todoRegex, true)
      when 'project' then @fetchRegexItem(todoRegex, true)
      else @fetchRegexItem(todoRegex)

    @searchPromise.then (result) =>
      @searching = false
      if result is 'cancelled'
        @emitter.emit 'did-cancel-search'
      else
        @emitter.emit 'did-finish-search'
    .catch (reason) =>
      @searching = false
      @emitter.emit 'did-fail-search', reason

  getSearchPaths: ->
    return [@getCustomPath()] if @scope is 'custom'

    ignores = atom.config.get('todog-atom.ignoreThesePaths')
    return ['*'] unless ignores?
    if Object.prototype.toString.call(ignores) isnt '[object Array]'
      @emitter.emit 'did-fail-search', "ignoreThesePaths must be an array"
      return ['*']
    "!#{ignore}" for ignore in ignores

  activeProjectHas: (filePath = '') ->
    return unless project = @getActiveProject()
    filePath.indexOf(project) is 0

  getActiveProject: ->
    return @activeProject if @activeProject
    @activeProject = project if project = @getFallbackProject()

  getFallbackProject: ->
    for item in atom.workspace.getPaneItems()
      if project = @projectForFile(item.getPath?())
        return project
    project if project = atom.project.getPaths()[0]

  getActiveProjectName: ->
    return 'no active project' unless project = @getActiveProject()
    projectName = path.basename(project)
    if projectName is 'undefined' then "no active project" else projectName

  setActiveProject: (filePath) ->
    lastProject = @activeProject
    @activeProject = project if project = @projectForFile(filePath)
    return false unless lastProject
    lastProject isnt @activeProject

  projectForFile: (filePath) ->
    return if typeof filePath isnt 'string'
    project if project = atom.project.relativizePath(filePath)[0]

  getMarkdown: ->
    todosMarkdown = new TodosMarkdown
    todosMarkdown.markdown @getFilteredTodos()

  cancelSearch: ->
    @searchPromise?.cancel?()

  # TODO: Previous searches are not saved yet!
  getPreviousSearch: ->
    sortBy = localStorage.getItem 'todog-atom.previous-sortBy'

  setPreviousSearch: (search) ->
    localStorage.setItem 'todog-atom.previous-search', search
