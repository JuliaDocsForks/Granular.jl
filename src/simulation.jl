## General simulation functions

export createSimulation
"""
    createSimulation([id::String="unnamed",
                      time_iteration::Int=0,
                      time::Float64=0.0,
                      time_total::Float64=-1.,
                      time_step::Float64=-1.,
                      file_time_step::Float64=-1.,
                      file_number::Int=0,
                      grains=Array{GrainCylindrical, 1}[],
                      ocean::Ocean,
                      atmosphere::Atmosphere)

Create a simulation object containing all relevant variables such as temporal 
parameters, and lists of grains and contacts.

The parameter `id` is used to uniquely identify the simulation when it is 
written to disk.
"""
function createSimulation(;id::String="unnamed",
                          time_iteration::Int=0,
                          time::Float64=0.0,
                          time_total::Float64=-1.,
                          time_step::Float64=-1.,
                          file_time_step::Float64=-1.,
                          file_number::Int=0,
                          file_time_since_output_file::Float64=0.,
                          grains=Array{GrainCylindrical, 1}[],
                          ocean::Ocean=createEmptyOcean(),
                          atmosphere::Atmosphere=createEmptyAtmosphere(),
                          Nc_max::Int=16)

    return Simulation(id,
                      time_iteration,
                      time,
                      time_total,
                      time_step,
                      file_time_step,
                      file_number,
                      file_time_since_output_file,
                      grains,
                      ocean,
                      atmosphere,
                      Nc_max)
end

export run!
"""
    run!(simulation[,
         verbose::Bool = true,
         status_interval = 100.,
         show_file_output = true,
         single_step = false,
         temporal_integration_method = "Three-term Taylor"],
         write_jld = false)

Run the `simulation` through time until `simulation.time` equals or exceeds 
`simulatim.time_total`.  This function requires that all grains are added to 
the simulation and that the length of the computational time step is adjusted 
accordingly.

The function will search for contacts, determine the force balance on each ice 
floe, and integrate all kinematic degrees of freedom accordingly.  The temporal 
integration is explicit and of length `simulation.time_step`.  This function 
will write VTK files to disk in the intervals `simulation.file_time_step` by the 
function `writeVTK`.  If this value is negative, no output files will be written 
to disk.

# Arguments
* `simulation::Simulation`: the simulation to run (object is modified)
* `verbose::Bool=true`: show verbose information during the time loop
* `status_interval::Bool=true`: show verbose information during the time loop
* `show_file_output::Bool=true`: report to stdout when output file is written
* `single_step::Bool=false`: run simulation for a single time step only.  If 
    this causes `simulation.time` to exceed `simulation.time_total`, the latter 
    is increased accordingly.
* `temporal_integration_method::String="Three-term Taylor"`: type of integration 
    method to use.  See `updateGrainKinematics` for details.
* `write_jld::Bool=false`: write simulation state to disk as JLD files (see 
    `Granular.writeSimulation(...)` whenever saving VTK output.
"""
function run!(simulation::Simulation;
              verbose::Bool=true,
              status_interval::Int=100,
              show_file_output::Bool=true,
              single_step::Bool=false,
              temporal_integration_method::String="Three-term Taylor",
              write_jld::Bool=false)

    if single_step && simulation.time >= simulation.time_total
        simulation.time_total += simulation.time_step
    end

    checkTimeParameters(simulation, single_step=single_step)

    # if both are enabled, check if the atmosphere grid spatial geometry is 
    # identical to the ocean grid
    if simulation.time_iteration == 0 &&
        typeof(simulation.atmosphere.input_file) != Bool &&  
        typeof(simulation.ocean.input_file) != Bool

        if simulation.ocean.xq ≈ simulation.atmosphere.xq &&
            simulation.ocean.yq ≈ simulation.atmosphere.yq
            if verbose
                info("identical ocean and atmosphere grids, turning on " * 
                     "optimizations")
            end
            simulation.atmosphere.collocated_with_ocean_grid = true
        end
    end


    # number of time steps between output files
    n_file_time_step = Int(ceil(simulation.file_time_step/simulation.time_step))

    while simulation.time <= simulation.time_total

        if simulation.file_time_step > 0.0 &&
            simulation.time_iteration % n_file_time_step == 0

            if show_file_output
                println()
            end
            if write_jld
                writeSimulation(simulation, verbose=show_file_output)
            end
            writeVTK(simulation, verbose=show_file_output)
            writeSimulationStatus(simulation, verbose=show_file_output)
            simulation.file_time_since_output_file = 0.0
        end

        if verbose && simulation.time_iteration % status_interval == 0
            reportSimulationTimeToStdout(simulation)
        end

        zeroForcesAndTorques!(simulation)

        if typeof(simulation.atmosphere.input_file) != Bool && 
            !simulation.atmosphere.collocated_with_ocean_grid
            sortGrainsInGrid!(simulation, simulation.atmosphere)
        end

        if typeof(simulation.ocean.input_file) != Bool
            sortGrainsInGrid!(simulation, simulation.ocean)
            findContacts!(simulation, method="ocean grid")

            if simulation.atmosphere.collocated_with_ocean_grid
                copyGridSortingInfo!(simulation.ocean, simulation.atmosphere,
                                     simulation.grains)
            end

        elseif typeof(simulation.atmosphere.input_file) != Bool
            findContacts!(simulation, method="atmosphere grid")

        else
            findContacts!(simulation, method="all to all")
        end

        interact!(simulation)

        if typeof(simulation.ocean.input_file) != Bool
            addOceanDrag!(simulation)
        end

        if typeof(simulation.atmosphere.input_file) != Bool
            addAtmosphereDrag!(simulation)
        end

        updateGrainKinematics!(simulation, method=temporal_integration_method)

        # Update time variables
        simulation.time_iteration += 1
        incrementCurrentTime!(simulation, simulation.time_step)

        if single_step
            return nothing
        end
    end

    if simulation.file_time_step > 0.0
        if show_file_output
            println()
        end
        writeParaviewPythonScript(simulation, verbose=show_file_output)
        writeSimulationStatus(simulation, verbose=show_file_output)
    end

    if verbose
        reportSimulationTimeToStdout(simulation)
        println()
    end
    gc()
    nothing
end

export addGrain!
"""
    addGrain!(simulation::Simulation,
                grain::GrainCylindrical,
                verbose::Bool = False)

Add an `grain` to the `simulation` object.  If `verbose` is true, a short 
confirmation message will be printed to stdout.
"""
function addGrain!(simulation::Simulation,
                     grain::GrainCylindrical,
                     verbose::Bool = False)
    push!(simulation.grains, grain)

    if verbose
        info("Added Grain $(length(simulation.grains))")
    end
    nothing
end

export disableGrain!
"Disable grain with index `i` in the `simulation` object."
function disableGrain!(simulation::Simulation, i::Int)
    if i < 1
        error("Index must be greater than 0 (i = $i)")
    end
    simulation.grains[i].enabled = false
    nothing
end

export zeroForcesAndTorques!
"Sets the `force` and `torque` values of all grains to zero."
function zeroForcesAndTorques!(simulation::Simulation)
    for grain in simulation.grains
        grain.force = grain.external_body_force
        grain.torque = 0.
        grain.pressure = 0.
    end
    nothing
end

export reportSimulationTimeToStdout
"Prints the current simulation time and total time to standard out"
function reportSimulationTimeToStdout(simulation::Simulation)
    print("\r  t = ", simulation.time, '/', simulation.time_total,
          " s            ")
    nothing
end

export compareSimulations
"""
    compareSimulations(sim1::Simulation, sim2::Simulation)

Compare values of two `Simulation` objects using the `Base.Test` framework.
"""
function compareSimulations(sim1::Simulation, sim2::Simulation)

    Test.@test sim1.id == sim2.id

    Test.@test sim1.time_iteration == sim2.time_iteration
    Test.@test sim1.time ≈ sim2.time
    Test.@test sim1.time_total ≈ sim2.time_total
    Test.@test sim1.time_step ≈ sim2.time_step
    Test.@test sim1.file_time_step ≈ sim2.file_time_step
    Test.@test sim1.file_number == sim2.file_number
    Test.@test sim1.file_time_since_output_file ≈ sim2.file_time_since_output_file

    for i=1:length(sim1.grains)
        compareGrains(sim1.grains[i], sim2.grains[i])
    end
    compareOceans(sim1.ocean, sim2.ocean)
    compareAtmospheres(sim1.atmosphere, sim2.atmosphere)

    Test.@test sim1.Nc_max == sim2.Nc_max
    nothing
end

export printMemoryUsage
"""
    printMemoryUsage(sim::Simulation)

Shows the memory footprint of the simulation object.
"""
function printMemoryUsage(sim::Simulation)
    
    reportMemory(sim, "sim")
    println("  where:")

    reportMemory(sim.grains, "    sim.grains", 
                 "(N=$(length(sim.grains)))")

    reportMemory(sim.ocean, "    sim.ocean",
                 "($(size(sim.ocean.xh, 1))x" *
                 "$(size(sim.ocean.xh, 2))x" *
                 "$(size(sim.ocean.xh, 3)))")

    reportMemory(sim.atmosphere, "    sim.atmosphere",
                 "($(size(sim.atmosphere.xh, 1))x" *
                 "$(size(sim.atmosphere.xh, 2))x" *
                 "$(size(sim.atmosphere.xh, 3)))")
    nothing
end

function reportMemory(variable, head::String, tail::String="")
    bytes = Base.summarysize(variable)
    if bytes < 10_000
        size_str = @sprintf "%5d bytes" bytes
    elseif bytes < 10_000 * 1024
        size_str = @sprintf "%5d kb" bytes ÷ 1024
    elseif bytes < 10_000 * 1024 * 1024
        size_str = @sprintf "%5d Mb" bytes ÷ 1024 ÷ 1024
    else
        size_str = @sprintf "%5d Gb" bytes ÷ 1024 ÷ 1024 ÷ 1024
    end
    @printf("%-20s %s %s\n", head, size_str, tail)
    nothing
end
