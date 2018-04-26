{CompositeDisposable} = require 'atom'
{View} = require 'atom-space-pen-views'

class ItemView extends View
  @content: (item) ->
    @span class: 'badge badge-large', 'data-id': item, item

class CodeView extends View
  @content: (item) ->
    @code item

module.exports =
class ShowTodoView extends View
  @content: ->
    @div outlet: 'todoOptions', class: 'todo-options', =>
      @div class: 'option', =>
        @h2 'On Table'
        @div outlet: 'itemsOnTable', class: 'block items-on-table'

      @div class: 'option', =>
        @h2 'Off Table'
        @div outlet: 'itemsOffTable', class: 'block items-off-table'

      @div class: 'option', =>
        @h2 'Ignore Paths'
        @div outlet: 'ignorePathDiv'

      @div class: 'option', =>
        @h2 'Auto Refresh'
        @div class: 'checkbox', =>
          @label =>
            @input outlet: 'autoRefreshCheckbox', class: 'input-checkbox', type: 'checkbox'

      @div class: 'option', =>
        @div class: 'btn-group', =>
          @button outlet: 'configButton', class: 'btn', "Go to Config"
          @button outlet: 'closeButton', class: 'btn', "Close Options"

  initialize: (@collection) ->
    @disposables = new CompositeDisposable
    @handleEvents()
    @updateUI()

  handleEvents: ->
    @configButton.on 'click', ->
      atom.workspace.open 'atom://config/packages/todog-atom'
    @closeButton.on 'click', =>
      @parent().slideToggle()
    @autoRefreshCheckbox.on 'click', (event) =>
      @autoRefreshChange(event.target.checked)

    @disposables.add atom.config.observe 'todog-atom.autoRefresh', (newValue) =>
      @autoRefreshCheckbox.context?.checked = newValue

  detach: ->
    @disposables.dispose()

  updateShowInTable: =>
    showInTable = @sortable.toArray()
    atom.config.set('todog-atom.showInTable', showInTable)

  updateUI: ->
    tableItems = atom.config.get('todog-atom.showInTable')
    for item in @collection.getAvailableTableItems()
      if tableItems.indexOf(item) is -1
        @itemsOffTable.append new ItemView(item)
      else
        @itemsOnTable.append new ItemView(item)

    Sortable = require 'sortablejs'

    @sortable = Sortable.create(
      @itemsOnTable.context
      group: 'tableItems'
      ghostClass: 'ghost'
      onSort: @updateShowInTable
    )

    Sortable.create(
      @itemsOffTable.context
      group: 'tableItems'
      ghostClass: 'ghost'
    )

    for path in atom.config.get('todog-atom.ignoreThesePaths')
      @ignorePathDiv.append new CodeView(path)

  autoRefreshChange: (state) ->
    atom.config.set('todog-atom.autoRefresh', state)
