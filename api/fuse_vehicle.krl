ruleset fuse_vehicle {
    meta {
      name "Fuse API for Vehicle"
      description <<
Fuse ruleset for a vehicle pico
    >>
      author "PJW"
      logging off


      use module b16x10 alias fuse_keys

      use module a169x676 alias pds
	
      provides vin

    }

    global {

        vin = function() {
            this_vin = pds:get_me("vin");

            (this_vin.isnull()) => "NO_VIN" | this_vin
        };

 
        initVehicle = defaction(vehicle_channel, vehicle_details) {
            vehicle = {
                "cid": vehicle_channel
            };
            
            {
                event:send(vehicle, "pds", "new_data_available")
                    with attrs = {
                        "namespace": "data",
                        "keyvalue": "detail",
                        "value": vehicle_details.delete(["eci"]).encode(),
                        "shouldRaiseGTourDoneEvent": "YES"
                    };

                event:send(fleetChannel(), "fuse", "new_pico") // should this be the same as the event that initializes the pico? 
                    with attrs = {
                        "details": vehicle_details.encode()
                    };
            }
        };

        updateVehicle = defaction(vehicle_channel, vehicle_details) {
            vehicle = {
                "cid": vehicle_channel
            };
            stale_details = sky:cloud(vehicle{"cid"}, "b501810x6", "detail");
            fresh_details = (not stale_details{"error"}) => stale_details.put(vehicle_details) | vehicle_details;
            
            {
                event:send(vehicle, "pds", "new_data_available")
                    with attrs = {
                        "namespace": "data",
                        "keyvalue": "detail",
                        "value": fresh_details.encode(),
                        "shouldRaiseGTourDoneEvent": "YES"
                    };


                event:send(fleetChannel(), "gtour", "did_amend_pico")
                    with attrs = {
                        "details": fresh_details.encode()
                    };
            }
        };

        destroyVehicle = defaction(lid) {
            vehicle_channel = sky:cloud(fleetChannel().pick("$.cid"), "b501810x4", "translate", {
                "id": lid
            });
            obilterated = CloudOS:cloudDestroy(vehicle_channel.pick("$.cid"));

            {
                event:send(fleetChannel(), "gtour", "did_destroy_pico")
                    with attrs = {
                        "id": lid
                    };
            }
        };

    }


   

}