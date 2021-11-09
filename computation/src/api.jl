using Genie, Genie.Cache

include("computation.jl")


Genie.config.run_as_server = true
Cache.init()

route("/MakeCtMesh", method = POST) do
	
    CT_fname, dose_sum_fname, rs_fname = jsonpayload()["ct_fname"], jsonpayload()["dose_fname"], jsonpayload()["rs_fname"]
    cache_key = CT_fname * dose_sum_fname * rs_fname
    dicoms = withcache(cache_key) do
        dose_data = load_DICOMs(CT_fname, dose_sum_fname, rs_fname)
        mesh_location = create_mesh_and_save(dose_data, cache_key)
    end
    
    return mesh_location
end

route("/MakeRoiMesh", method = POST) do
    CT_fname, dose_sum_fname, rs_fname = jsonpayload()["ct_fname"], jsonpayload()["dose_fname"], jsonpayload()["rs_fname"]
    roi_mesh = jsonpayload()["roi_mesh"]

    cache_key = CT_fname * dose_sum_fname * rs_fname
    dicoms = withcache(cache_key) do
        dose_data = load_DICOMs(CT_fname, dose_sum_fname, rs_fname)
    end
    
    mesh_location = withcache(cache_key * roi_mesh) do
        make_ROI_mesh(dose_data, roi_name, cache_key)
    end
    
    return mesh_location
end

Genie.startup(8000, "127.0.0.1", async=false)



# TODO
# 1. cache output. load_DICOMs
# 2. ct_mesh_from_files // Creating all dicoms, and save to file, so it can be transfered to clinet 
# 3. make_ROI_mesh // creating mesh for one ROI 