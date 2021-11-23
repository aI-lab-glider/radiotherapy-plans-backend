using Genie, Genie.Cache
using DotEnv
config = DotEnv.config()



include("computation.jl")



Genie.config.run_as_server = true
Cache.init()

route("/MakeCtMesh", method = POST) do
    payload = jsonpayload()
    CT_fname, dose_sum_fname, rs_fname = payload["ct_fname"], payload["dose_fname"], payload["rs_fname"]
    cache_key = CT_fname * dose_sum_fname * rs_fname
    dicoms = withcache(cache_key) do
        upload_dir = config["UPLOAD_DIR"]
        dose_data = load_DICOMs(upload_dir * CT_fname, upload_dir * dose_sum_fname, upload_dir * rs_fname)
        mesh_location = create_mesh_and_save(upload_dir * dose_data, upload_dir * cache_key)
    end

    return mesh_location
end

route("/MakeRoiMesh", method = POST) do
    payload = jsonpayload()
    CT_fname, dose_sum_fname, rs_fname = payload["ct_fname"], payload["dose_fname"], payload["rs_fname"]
    roi_mesh = payload["roi_mesh"]

    cache_key = CT_fname * dose_sum_fname * rs_fname
    dicoms = withcache(cache_key) do
        dose_data = load_DICOMs(CT_fname, dose_sum_fname, rs_fname)
    end

    mesh_location = withcache(cache_key * roi_mesh) do
        make_ROI_mesh(dose_data, roi_name, cache_key)
    end

    return mesh_location
end

port = config["GENIE_PORT"]
Genie.startup(parse(Int64, port), "127.0.0.1", async = false)
