{CompositeDisposable} = require 'atom'
{View, $} = require 'atom-space-pen-views'

{TableHeaderView, TodoView, TodoEmptyView} = require './todo-item-view'

module.exports =
class ShowTodoView extends View
  @content: ->
    @div class: 'todo-table', tabindex: -1, =>
      @table outlet: 'table'

  initialize: (@collection) ->
    @disposables = new CompositeDisposable
    @handleConfigChanges()
    @handleEvents()

  handleEvents: ->
    # @disposables.add @collection.onDidAddTodo @renderTodo
    @disposables.add @collection.onDidFinishSearch @initTable
    @disposables.add @collection.onDidRemoveTodo @removeTodo
    @disposables.add @collection.onDidClear @clearTodos
    @disposables.add @collection.onDidSortTodos (todos) => @renderTable todos
    @disposables.add @collection.onDidFilterTodos (todos) => @renderTable todos

    @on 'click', 'th', @tableHeaderClicked

  handleConfigChanges: ->
    @disposables.add atom.config.onDidChange 'todog-atom.showInTable', ({newValue, oldValue}) =>
      @showInTable = newValue
      @renderTable @collection.getTodos()

    @disposables.add atom.config.onDidChange 'todog-atom.sortBy', ({newValue, oldValue}) =>
      @sort(@sortBy = newValue, @sortAsc)

    @disposables.add atom.config.onDidChange 'todog-atom.sortAscending', ({newValue, oldValue}) =>
      @sort(@sortBy, @sortAsc = newValue)

  destroy: ->
    @disposables.dispose()
    @empty()

  initTable: =>
    @showInTable = atom.config.get('todog-atom.showInTable')
    @sortBy = atom.config.get('todog-atom.sortBy')
    @sortAsc = atom.config.get('todog-atom.sortAscending')
    @sort(@sortBy, @sortAsc)

  renderTableHeader: ->
    @table.append new TableHeaderView(@showInTable, {@sortBy, @sortAsc})

  tableHeaderClicked: (e) =>
    item = e.target.innerText
    sortAsc = if @sortBy is item then !@sortAsc else @sortAsc

    atom.config.set('todog-atom.sortBy', item)
    atom.config.set('todog-atom.sortAscending', sortAsc)

  renderTodo: (todo) =>
    @table.append new TodoView(@showInTable, todo)

  removeTodo: (todo) ->
    console.log 'removeTodo'

  clearTodos: =>
    @table.empty()

  renderTable: (todos) =>
    @clearTodos()
    @renderTableHeader()

    for todo in todos = todos
      @renderTodo(todo)
    @table.append new TodoEmptyView(@showInTable) unless todos.length

  sort: (sortBy, sortAsc) ->
    @collection.sortTodos(sortBy: sortBy, sortAsc: sortAsc)