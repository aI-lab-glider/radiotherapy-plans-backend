
#	REST API allowing for executing different functions from the application's backend
#	the method name corresponds to the function name, but is written in CamelCase, example:
#	<hosting url>/MakeRoiMesh	->	calls the make_ROI_mesh method

Genie.config.run_as_server = true

route("/MakeCtMesh", method = POST) do
	message = jsonpayload()
	@show message
	"Received message"
end

route("/MakeRoiMesh", method = POST) do
	message = jsonpayload()
	@show jsonpayload()

	"Received message"
end

Genie.startup(8000, "127.0.0.1", async=false)



# TODO
# 1. cache output. load_DICOMs
# 2. ct_mesh_from_files // Creating all dicoms, and save to file, so it can be transfered to clinet 
# 3. make_ROI_mesh // creating mesh for one ROI 