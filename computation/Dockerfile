FROM julia:1.7.0

WORKDIR /computation

COPY / /computation

RUN julia --project=/computation -e "using Pkg; Pkg.instantiate(); Pkg.precompile();"

CMD ["julia", "--project=/computation", "/computation/src/api.jl"]

