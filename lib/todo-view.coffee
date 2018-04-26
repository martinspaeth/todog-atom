{CompositeDisposable, TextBuffer} = require 'atom'
{ScrollView, TextEditorView} = require 'atom-space-pen-views'
path = require 'path'
fs = require 'fs-plus'

TodoTable = require './todo-table-view'
TodoOptions = require './todo-options-view'

deprecatedTextEditor = (params) ->
  if atom.workspace.buildTextEditor?
    atom.workspace.buildTextEditor(params)
  else
    TextEditor = require('atom').TextEditor
    new TextEditor(params)

module.exports =
class ShowTodoView extends ScrollView
  @content: (collection, filterBuffer) ->
    filterEditor = deprecatedTextEditor(
      mini: true
      tabLength: 2
      softTabs: true
      softWrapped: false
      buffer: filterBuffer
      placeholderText: 'Search Todos'
    )

    @div class: 'show-todo-preview', tabindex: -1, =>
      @div class: 'input-block', =>
        @div class: 'input-block-item input-block-item--flex', =>
          @subview 'filterEditorView', new TextEditorView(editor: filterEditor)
        @div class: 'input-block-item', =>
          @div class: 'btn-group', =>
            @button outlet: 'issueButton', class: 'btn'
            @button outlet: 'scopeButton', class: 'btn'
            @button outlet: 'optionsButton', class: 'btn icon-gear'
            @button outlet: 'refreshButton', class: 'btn icon-sync'

      @div class: 'input-block todo-info-block', =>
        @div class: 'input-block-item', =>
          @span outlet: 'todoInfo'

      @div outlet: 'optionsView'

      @div outlet: 'todoLoading', class: 'todo-loading', =>
        @div class: 'markdown-spinner'
        @h5 outlet: 'searchCount', class: 'text-center', "Loading Todos..."

      @subview 'todoTable', new TodoTable(collection)

  constructor: (@collection, @uri) ->
    super @collection, @filterBuffer = new TextBuffer

  initialize: ->
    @disposables = new CompositeDisposable
    @handleEvents()
    @setScopeButtonState(@collection.getSearchScope())
    @setIssueButtonState(@collection.getIssueNumber())

    @onlySearchWhenVisible = true
    @notificationOptions =
      detail: 'Atom todog package'
      dismissable: true
      icon: @getIconName()

    @checkDeprecation()

    @disposables.add atom.tooltips.add @issueButton, title: "Search for current issue"
    @disposables.add atom.tooltips.add @scopeButton, title: "What to Search"
    @disposables.add atom.tooltips.add @optionsButton, title: "Show Todo Options"
    # @disposables.add atom.tooltips.add @exportButton, title: "Export Todos"
    @disposables.add atom.tooltips.add @refreshButton, title: "Refresh Todos"

  handleEvents: ->
    @disposables.add atom.commands.add @element,
      'core:export': (event) =>
        event.stopPropagation()
        @export()
      'core:refresh': (event) =>
        event.stopPropagation()
        @search(true)

    @disposables.add @collection.onDidStartSearch @startLoading
    @disposables.add @collection.onDidFinishSearch @stopLoading
    @disposables.add @collection.onDidFailSearch (err) =>
      @searchCount.text "Search Failed"
      console.error err if err
      @showError err if err

    @disposables.add @collection.onDidChangeSearchScope (scope) =>
      @setScopeButtonState(scope)
      @search(true)

    @disposables.add @collection.onDidChangeIssueNumber (issueNumber) =>
      @setIssueButtonState(issueNumber)
      @search(true)

    @disposables.add @collection.onDidSearchPaths (nPaths) =>
      @searchCount.text "#{nPaths} paths searched..."

    @disposables.add atom.workspace.onDidChangeActivePaneItem (item) =>
      if @collection.setActiveProject(item?.getPath?()) or
      (item?.constructor.name is 'TextEditor' and @collection.scope is 'active')
        @search()

    @disposables.add atom.workspace.onDidAddTextEditor ({textEditor}) =>
      @search() if @collection.scope is 'open'

    @disposables.add atom.workspace.onDidDestroyPaneItem ({item}) =>
      @search() if @collection.scope is 'open'

    @disposables.add atom.workspace.observeTextEditors (editor) =>
      @disposables.add editor.onDidSave =>
        @search()

    @filterEditorView.getModel().onDidStopChanging =>
      @filter() if @firstTimeFilter
      @firstTimeFilter = true

    @issueButton.on 'click', @toggleIssueScope
    @scopeButton.on 'click', @toggleSearchScope
    @optionsButton.on 'click', @toggleOptions
    # @exportButton.on 'click', @export
    @refreshButton.on 'click', => @search(true)

  destroy: ->
    @collection.cancelSearch()
    @disposables.dispose()
    @detach()

  serialize: ->
    deserializer: 'todog/todo-view'
    scope: @collection.scope
    customPath: @collection.getCustomPath()

  getTitle: -> "Todo Show"
  getIconName: -> "checklist"
  getURI: -> @uri
  getDefaultLocation: -> 'right'
  getAllowedLocations: -> ['left', 'right', 'bottom']
  getProjectName: -> @collection.getActiveProjectName()
  getProjectPath: -> @collection.getActiveProject()

  getTodos: -> @collection.getTodos()
  getTodosCount: -> @collection.getTodosCount()
  isSearching: -> @collection.getState()
  search: (force = false) ->
    if @onlySearchWhenVisible
      return unless atom.workspace.paneContainerForItem(this)?.isVisible()
    @collection.search(force)

  startLoading: =>
    @todoLoading.show()
    @updateInfo()

  stopLoading: =>
    @todoLoading.hide()
    @updateInfo()

  updateInfo: ->
    @todoInfo.html("#{@getInfoText()} #{@getScopeText()}")

  getInfoText: ->
    return "Found ... results" if @isSearching()
    switch count = @getTodosCount()
      when 1 then "Found #{count} result"
      else "Found #{count} results"

  getScopeText: ->
    # TODO: Also show number of files

    switch @collection.scope
      when 'active'
        "in active file"
      when 'open'
        "in open files"
      when 'project'
        "in project <code>#{@getProjectName()}</code>"
      when 'custom'
        "in <code>#{@collection.customPath}</code>"
      else
        "in workspace"

  showError: (message = '') ->
    atom.notifications.addError message.toString(), @notificationOptions

  showWarning: (message = '') ->
    atom.notifications.addWarning message.toString(), @notificationOptions

  export: =>
    return if @isSearching()

    filePath = "#{@getProjectName() or 'todos'}.md"
    if projectPath = @getProjectPath()
      filePath = path.join(projectPath, filePath)

    # Do not override if default file path already exists
    filePath = undefined if fs.existsSync(filePath)

    atom.workspace.open(filePath).then (textEditor) =>
      textEditor.setText(@collection.getMarkdown())

  toggleSearchScope: =>
    scope = @collection.toggleSearchScope()
    @setScopeButtonState(scope)

  toggleIssueScope: =>
    issueNumber = @collection.toggleIssueScope()
    @setIssueButtonState(issueNumber)
    @collection.filterTodos @filterBuffer.getText()

  setIssueButtonState: (issueNumber) =>
    if !issueNumber?
      @issueButton.text 'All Todo\'s'
    else
      @issueButton.text '#' + issueNumber

  setScopeButtonState: (state) =>
    switch state
      when 'project' then @scopeButton.text 'Project'
      when 'open' then @scopeButton.text 'Open Files'
      when 'active' then @scopeButton.text 'Active File'
      when 'custom' then @scopeButton.text 'Custom'
      else @scopeButton.text 'Workspace'

  toggleOptions: =>
    unless @todoOptions
      @optionsView.hide()
      @todoOptions = new TodoOptions(@collection)
      @optionsView.html @todoOptions
    @optionsView.slideToggle()

  filter: ->
    @collection.filterTodos @filterBuffer.getText()

  checkDeprecation: ->
    if atom.config.get('todog-atom.findTheseRegexes')
      @showWarning '''
      Deprecation Warning:\n
      `findTheseRegexes` config is deprecated, please use `findTheseTodos` and `findUsingRegex` for custom behaviour.
      See https://github.com/mrodalgaard/atom-todog#config for more information.
      '''
