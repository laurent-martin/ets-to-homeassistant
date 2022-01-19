lambda do |knxconf|
  # get data to manipulate
  knx=knxconf.data
  objid=0
  knx[:ga].each do |id,ga|
    if ga[:objs].empty?
      puts "empty: #{ga}"
      function={
        name:   ga[:name],
        type:   :custom, # unknown, so assume just switch
        ga:     [id],
        floor:  'unknown floor',
        room:   'unknown room',
        custom: {ha_type: 'switch'} # custom values
      }
      knx[:ob][objid]=function
      objid+=1
    end
  end

end
