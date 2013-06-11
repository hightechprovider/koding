class VMMainView extends JView

  constructor:(options={}, data)->

    options.cssClass or= "vms"
    data or= {}
    super options, data

    @vm = KD.getSingleton 'vmController'
    @vm.on 'StateChanged', @bound 'checkVMState'
    @vmList = []

    @vmListController = new KDListViewController
      startWithLazyLoader : no
      viewOptions         :
        type              : "vm-list"
        cssClass          : "vm-list"
        itemClass         : VMListItemView


    @vmListView = @vmListController.getView()

    @on "Clicked", (item)=>
      @graphView.update? item
      @vmListController.deselectAllItems()
      @vmListController.selectSingleItem item

    @graphView = new VMDetailView
      cssClass  : 'vm-details'

    @splitView = new KDSplitView
      type      : 'vertical'
      resizable : no
      sizes     : ['40%', '70%']
      views     : [@vmListView, @graphView]

    @vmListController.on "ItemSelectionPerformed", (listController, {event, items})=>
      @graphView.update items[0].data

    @loadItems()

  checkVMState:(err, vm, info)->
    if not @vmList[vm]
      @loadItems()
    else if info.state is "RUNNING"
      @vmList[vm].updateStatus yes
    else
      @vmList[vm].updateStatus no

  getVMInfo: (vmName, callback)->
    kc = KD.singletons.kiteController
    kc.run
      kiteName  : 'os',
      vmName    : vmName,
      method    : 'vm.info'
    , callback

  loadItems:->
    @vmListController.removeAllItems()
    @vmListController.showLazyLoader no

    KD.remote.api.JVM.fetchVms (err, vms)=>
      if err
        @vmListController.hideLazyLoader()
      else
        stack = []
        vms.forEach (name)=>
          stack.push (cb)=>

            @getVMInfo name, (err, info)=>
              if err or info.state != 'RUNNING'
                status = no
              else
                status = yes

              cb null, {
                vmName : name
                group  : 'Koding'
                domain : 'bahadir.kd.io'
                type   : 'personal'
                status : status
                controller : @
              }

        async.parallel stack, (err, results)=>
          @vmListController.hideLazyLoader()
          unless err
            items = @vmListController.instantiateListItems results
            @vmListController.selectSingleItem items[0]

  pistachio:->
    """
      {{> @splitView}}
    """


class VMDetailView extends KDView
  constructor: (options, data) ->
    options.cssClass or= "vm-details"
    super options, data

    @vmTitle = new KDLabelView
      title: 'VM Name'

  update: (data)->
    @vmTitle.updateTitle data.vmName

  viewAppended:()->
    super()

    @setTemplate @pistachio()
    @template.update()

  pistachio:->
    """
      <h2>VM: {{> @vmTitle}}</h2>
    """

class VMListItemView extends KDListItemView
  constructor: (options, data) ->
    options.cssClass or= "vm-item"
    options.click = @bound "clicked"
    super options, data

    {controller,vmName} = @getData()
    controller.vmList[vmName] = @

    @statusIcon = new KDCustomHTMLView
      tagName  : "span"
      cssClass : "vm-status"

    @switch = new KDOnOffSwitch
      size         : 'tiny'
      labels       : ['I', 'O']
      defaultValue : data.status
      cssClass     : 'fr'
      callback : (state)=>
        if state
        then controller.vm.start vmName
        else controller.vm.stop  vmName

    @updateStatus @getData().status

  clicked: (event)->
    @getData().controller.emit "Clicked", @

  updateStatus:(state)->
    unless state
      @statusIcon.unsetClass "vm-status-on"
      @switch.setOff no
    else
      @statusIcon.setClass "vm-status-on"
      @switch.setOn no

  viewAppended:()->
    super()

    @setTemplate @pistachio()
    @template.update()

  pistachio: ->
    data = @getData()
    """
    <div>
      <span class="vm-icon #{data.type}"></span>
      {{> @statusIcon }}
      <span class="vm-title">
        #{data.vmName} - #{data.group}
      </span>
      <span class="vm-domain">http://#{data.domain}</span>
      {{> @switch }}
    </div>
    """