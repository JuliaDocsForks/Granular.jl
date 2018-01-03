#!/usr/bin/env julia

info("#### $(basename(@__FILE__)) ####")

info("Testing memory footprint of Granular types")

sim = Granular.createSimulation()
empty_sim_size = 104
empty_sim_size_recursive = 752

@test sizeof(sim) == empty_sim_size
@test Base.summarysize(sim) == empty_sim_size_recursive

size_per_grain = 384
size_per_grain_recursive = 2608   # Nc_max = 32

info("Testing memory usage when adding grains")
for i=1:100
    Granular.addGrainCylindrical!(sim, [1., 1.], 1., 1., verbose=false)

    @test sizeof(sim) == empty_sim_size

    @test sizeof(sim.grains[i]) == size_per_grain
    @test Base.summarysize(sim.grains[i]) == size_per_grain_recursive

    @test sizeof(sim.grains) == sizeof(Int)*i
    @test sizeof(sim.grains[:]) == sizeof(Int)*i
    @test Base.summarysize(sim.grains) == size_per_grain_recursive*i + 
        sizeof(Int)*i

    @test Base.summarysize(sim) == empty_sim_size_recursive + sizeof(Int)*i + 
        size_per_grain_recursive*i

    @test Base.summarysize(sim.grains[i]) == size_per_grain_recursive
end

info("Checking memory footprint when overwriting simulation object")
sim = Granular.createSimulation()
@test sizeof(sim) == empty_sim_size
@test Base.summarysize(sim) == empty_sim_size_recursive

info("Check memory usage when stepping time for empty simulation object")
sim = Granular.createSimulation()
sim.time_step = 1.0
for i=1:10
    Granular.run!(sim, single_step=true, verbose=false)
    @test sizeof(sim) == empty_sim_size
    @test Base.summarysize(sim) == empty_sim_size_recursive
end

info("Check memory when stepping time with single ice floe")
sim = Granular.createSimulation()
Granular.addGrainCylindrical!(sim, [1., 1.], 1., 1., verbose=false)
sim.time_step = 1.0
for i=1:10
    Granular.run!(sim, single_step=true, verbose=false)
    @test sizeof(sim) == empty_sim_size
    @test Base.summarysize(sim) == empty_sim_size_recursive + 
        sizeof(Int)*length(sim.grains) + 
        size_per_grain_recursive*length(sim.grains)
end

info("Check memory when stepping time with two separate grains")
sim = Granular.createSimulation()
Granular.addGrainCylindrical!(sim, [1., 1.], 1., 1., verbose=false)
Granular.addGrainCylindrical!(sim, [1., 1.], 3., 1., verbose=false)
sim.time_step = 1.0
for i=1:10
    Granular.run!(sim, single_step=true, verbose=false)
    @test sizeof(sim) == empty_sim_size
    @test Base.summarysize(sim) == empty_sim_size_recursive + 
        sizeof(Int)*length(sim.grains) + 
        size_per_grain_recursive*length(sim.grains)
end

info("Check memory when stepping time with two interacting grains (all to all)")
sim = Granular.createSimulation()
Granular.addGrainCylindrical!(sim, [1., 1.], 1., 1., verbose=false)
Granular.addGrainCylindrical!(sim, [1., 1.], 1.9, 1., verbose=false)
sim.time_step = 1.0
for i=1:10
    Granular.run!(sim, single_step=true, verbose=false)
    @test sizeof(sim) == empty_sim_size
    @test Base.summarysize(sim) == empty_sim_size_recursive + 
        sizeof(Int)*length(sim.grains) + 
        size_per_grain_recursive*length(sim.grains)
end

info("Check memory when stepping time with two interacting grains (cell sorting)")
sim = Granular.createSimulation()
Granular.addGrainCylindrical!(sim, [1., 1.], 1., 1., verbose=false)
Granular.addGrainCylindrical!(sim, [1., 1.], 1.9, 1., verbose=false)
nx, ny, nz = 5, 5, 1
sim.ocean = Granular.createRegularOceanGrid([nx, ny, nz], [10., 10., 10.])
sim.time_step = 1e-6
Granular.run!(sim, single_step=true, verbose=false)
original_size_recursive = Base.summarysize(sim)
for i=1:10
    Granular.run!(sim, single_step=true, verbose=false)
    @test Base.summarysize(sim) == original_size_recursive
end

info("Checking if memory is freed after ended collision (all to all)")
sim = Granular.createSimulation(id="test")
Granular.addGrainCylindrical!(sim, [1., 1.], 10., 1., verbose=false)
Granular.addGrainCylindrical!(sim, [21.05, 1.], 10., 1., verbose=false)
sim.grains[1].lin_vel[1] = 0.1
Granular.setTotalTime!(sim, 10.0)
Granular.setTimeStep!(sim, epsilon=0.07, verbose=false)
original_size_recursive = Base.summarysize(sim)
Granular.run!(sim, verbose=false)
@test Base.summarysize(sim) == original_size_recursive

info("Checking if memory is freed after ended collision (cell sorting)")
sim = Granular.createSimulation(id="test")
Granular.addGrainCylindrical!(sim, [1., 1.], 10., 1., verbose=false)
Granular.addGrainCylindrical!(sim, [21.05, 1.], 10., 1., verbose=false)
sim.ocean = Granular.createRegularOceanGrid([2, 2, 2], [40., 40., 10.])
sim.grains[1].lin_vel[1] = 0.1
Granular.setTotalTime!(sim, 10.0)
Granular.setTimeStep!(sim, epsilon=0.07, verbose=false)
Granular.run!(sim, single_step=true, verbose=false)
original_sim_size_recursive = Base.summarysize(sim)
original_grains_size_recursive = Base.summarysize(sim.grains)
original_ocean_size_recursive = Base.summarysize(sim.ocean)
original_atmosphere_size_recursive = Base.summarysize(sim.atmosphere)
Granular.run!(sim, verbose=false)
@test Base.summarysize(sim.grains) == original_grains_size_recursive
@test Base.summarysize(sim.ocean) == original_ocean_size_recursive
@test Base.summarysize(sim.atmosphere) == original_atmosphere_size_recursive
@test Base.summarysize(sim) == original_sim_size_recursive

sim = Granular.createSimulation(id="test")
Granular.addGrainCylindrical!(sim, [1., 1.], 10., 1., verbose=false)
Granular.addGrainCylindrical!(sim, [21.05, 1.], 10., 1., verbose=false)
sim.atmosphere = Granular.createRegularAtmosphereGrid([2, 2, 2], [40., 40., 10.])
sim.grains[1].lin_vel[1] = 0.1
Granular.setTotalTime!(sim, 10.0)
Granular.setTimeStep!(sim, epsilon=0.07, verbose=false)
Granular.run!(sim, single_step=true, verbose=false)
original_sim_size_recursive = Base.summarysize(sim)
original_grains_size_recursive = Base.summarysize(sim.grains)
original_ocean_size_recursive = Base.summarysize(sim.ocean)
original_atmosphere_size_recursive = Base.summarysize(sim.atmosphere)
Granular.run!(sim, verbose=false)
@test Base.summarysize(sim.grains) == original_grains_size_recursive
@test Base.summarysize(sim.ocean) == original_ocean_size_recursive
@test Base.summarysize(sim.atmosphere) == original_atmosphere_size_recursive
@test Base.summarysize(sim) == original_sim_size_recursive

sim = Granular.createSimulation(id="test")
Granular.addGrainCylindrical!(sim, [1., 1.], 10., 1., verbose=false)
Granular.addGrainCylindrical!(sim, [21.05, 1.], 10., 1., verbose=false)
sim.atmosphere = Granular.createRegularAtmosphereGrid([2, 2, 2], [40., 40., 10.])
sim.ocean = Granular.createRegularOceanGrid([2, 2, 2], [40., 40., 10.])
sim.grains[1].lin_vel[1] = 0.1
Granular.setTotalTime!(sim, 10.0)
Granular.setTimeStep!(sim, epsilon=0.07, verbose=false)
Granular.run!(sim, single_step=true, verbose=false)
original_sim_size_recursive = Base.summarysize(sim)
original_grains_size_recursive = Base.summarysize(sim.grains)
original_ocean_size_recursive = Base.summarysize(sim.ocean)
original_atmosphere_size_recursive = Base.summarysize(sim.atmosphere)
Granular.run!(sim, verbose=false)
@test Base.summarysize(sim.grains) == original_grains_size_recursive
@test Base.summarysize(sim.ocean) == original_ocean_size_recursive
@test Base.summarysize(sim.atmosphere) == original_atmosphere_size_recursive
@test Base.summarysize(sim) == original_sim_size_recursive

Granular.printMemoryUsage(sim)
