using Genie, Genie.Cache, Genie.Requests
using DotEnv
config = DotEnv.config()



include("computation.jl")



Genie.config.run_as_server = true
Cache.init()

route("/MakeCtMesh", method = POST) do
    payload = jsonpayload()
    CT_fname, dose_sum_fname, rs_fname, save_to = payload["ct_fname"], payload["dose_fname"], payload["rs_fname"], payload["save_to"]
    upload_dir = config["UPLOAD_DIR"]
    save_to = joinpath(upload_dir, save_to)
    dicoms = withcache(save_to) do
        CT_fname, dose_sum_fname, rs_fname = [joinpath(upload_dir, f_name) for f_name in [CT_fname, dose_sum_fname, rs_fname]]
        dose_data = load_DICOMs(CT_fname, dose_sum_fname, rs_fname)
        create_mesh_and_save(dose_data, save_to)
    end
    return save_to
end

route("/MakeRoiMesh", method = POST) do
    payload = jsonpayload()
    CT_fname, dose_sum_fname, rs_fname = payload["ct_fname"], payload["dose_fname"], payload["rs_fname"]
    f_name, save_cold, save_hot = payload["save_to"], payload["save_cold"], payload["save_hot"]
    roi_name = payload["roi_name"]
    hot_cold_level = convert(Float64, payload["hot_cold_level"])
    dose_data = load_DICOMs(CT_fname, dose_sum_fname, rs_fname)
    make_ROI_mesh(dose_data, roi_name, f_name)
    create_hot_cold_meshes(dose_data, hot_cold_level, roi_name, save_cold, save_hot)

    return f_name
end

port = config["GENIE_PORT"]
Genie.startup(parse(Int64, port), "127.0.0.1", async = false)
