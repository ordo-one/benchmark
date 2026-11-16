// swiftlint:disable all
//
// Copyright (c) 2022 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

// This file was generated from JSON Schema using quicktype, do not modify it directly.

// Generated using https://app.quicktype.io with paired down output from
// let optionString = "J"
// malloc_stats_print(nil, nil, optionString)

#if canImport(jemalloc)

// MARK: - Pokedex

struct Pokedex: Codable {
    let jemalloc: Jemalloc
}

// MARK: - Jemalloc

struct Jemalloc: Codable {
    let version: String
    let config: Config
    let opt: Opt
    let arenas: Arenas
    let stats: Stats
    let statsArenas: StatsArenas

    enum CodingKeys: String, CodingKey {
        case version, config, opt, arenas, stats
        case statsArenas = "stats.arenas"
    }
}

// MARK: - Arenas

struct Arenas: Codable {
    let narenas, dirtyDecayMS, muzzyDecayMS, quantum: Int
    let page, tcacheMax, nbins, nhbins: Int
    let bin: [ArenasBin]
    let nlextents: Int
    let lextent: [ArenasLextent]

    enum CodingKeys: String, CodingKey {
        case narenas
        case dirtyDecayMS = "dirty_decay_ms"
        case muzzyDecayMS = "muzzy_decay_ms"
        case quantum, page
        case tcacheMax = "tcache_max"
        case nbins, nhbins, bin, nlextents, lextent
    }
}

// MARK: - ArenasBin

struct ArenasBin: Codable {
    let size, nregs, slabSize, nshards: Int

    enum CodingKeys: String, CodingKey {
        case size, nregs
        case slabSize = "slab_size"
        case nshards
    }
}

// MARK: - ArenasLextent

struct ArenasLextent: Codable {
    let size: Double
}

// MARK: - Config

struct Config: Codable {
    let cacheOblivious, debug, fill, lazyLock: Bool
    let mallocConf: String
    let optSafetyChecks, prof, profLibgcc, profLibunwind: Bool
    let stats, utrace, xmalloc: Bool

    enum CodingKeys: String, CodingKey {
        case cacheOblivious = "cache_oblivious"
        case debug, fill
        case lazyLock = "lazy_lock"
        case mallocConf = "malloc_conf"
        case optSafetyChecks = "opt_safety_checks"
        case prof
        case profLibgcc = "prof_libgcc"
        case profLibunwind = "prof_libunwind"
        case stats, utrace, xmalloc
    }
}

// MARK: - Opt

struct Opt: Codable {
    let abort, abortConf, cacheOblivious, confirmConf: Bool
    let retain: Bool
    let dss: String
    let narenas: Int
    let percpuArena: String
    let oversizeThreshold: Int
    let hpa: Bool
    let hpaSlabMaxAlloc, hpaHugificationThreshold, hpaHugifyDelayMS, hpaMinPurgeIntervalMS: Int
    let hpaDirtyMult: String
    let hpaSECNshards, hpaSECMaxAlloc, hpaSECMaxBytes, hpaSECBytesAfterFlush: Int
    let hpaSECBatchFillExtra: Int
    let metadataThp: String
    let mutexMaxSpin, dirtyDecayMS, muzzyDecayMS, lgExtentMaxActiveFit: Int
    let junk: String
    let zero, experimentalInfallibleNew, tcache: Bool
    let tcacheMax, tcacheNslotsSmallMin, tcacheNslotsSmallMax, tcacheNslotsLarge: Int
    let lgTcacheNslotsMul, tcacheGcIncrBytes, tcacheGcDelayBytes, lgTcacheFlushSmallDiv: Int
    let lgTcacheFlushLargeDiv: Int
    let thp: String
    let statsPrint: Bool
    let statsPrintOpts: String
    let statsInterval: Int
    let statsIntervalOpts, zeroRealloc: String

    enum CodingKeys: String, CodingKey {
        case abort
        case abortConf = "abort_conf"
        case cacheOblivious = "cache_oblivious"
        case confirmConf = "confirm_conf"
        case retain, dss, narenas
        case percpuArena = "percpu_arena"
        case oversizeThreshold = "oversize_threshold"
        case hpa
        case hpaSlabMaxAlloc = "hpa_slab_max_alloc"
        case hpaHugificationThreshold = "hpa_hugification_threshold"
        case hpaHugifyDelayMS = "hpa_hugify_delay_ms"
        case hpaMinPurgeIntervalMS = "hpa_min_purge_interval_ms"
        case hpaDirtyMult = "hpa_dirty_mult"
        case hpaSECNshards = "hpa_sec_nshards"
        case hpaSECMaxAlloc = "hpa_sec_max_alloc"
        case hpaSECMaxBytes = "hpa_sec_max_bytes"
        case hpaSECBytesAfterFlush = "hpa_sec_bytes_after_flush"
        case hpaSECBatchFillExtra = "hpa_sec_batch_fill_extra"
        case metadataThp = "metadata_thp"
        case mutexMaxSpin = "mutex_max_spin"
        case dirtyDecayMS = "dirty_decay_ms"
        case muzzyDecayMS = "muzzy_decay_ms"
        case lgExtentMaxActiveFit = "lg_extent_max_active_fit"
        case junk, zero
        case experimentalInfallibleNew = "experimental_infallible_new"
        case tcache
        case tcacheMax = "tcache_max"
        case tcacheNslotsSmallMin = "tcache_nslots_small_min"
        case tcacheNslotsSmallMax = "tcache_nslots_small_max"
        case tcacheNslotsLarge = "tcache_nslots_large"
        case lgTcacheNslotsMul = "lg_tcache_nslots_mul"
        case tcacheGcIncrBytes = "tcache_gc_incr_bytes"
        case tcacheGcDelayBytes = "tcache_gc_delay_bytes"
        case lgTcacheFlushSmallDiv = "lg_tcache_flush_small_div"
        case lgTcacheFlushLargeDiv = "lg_tcache_flush_large_div"
        case thp
        case statsPrint = "stats_print"
        case statsPrintOpts = "stats_print_opts"
        case statsInterval = "stats_interval"
        case statsIntervalOpts = "stats_interval_opts"
        case zeroRealloc = "zero_realloc"
    }
}

// MARK: - Stats

struct Stats: Codable {
    let allocated, active, metadata, metadataThp: Int
    let resident, mapped, retained, zeroReallocs: Int
    let backgroundThread: StatsBackgroundThread
    let mutexes: Mutexes

    enum CodingKeys: String, CodingKey {
        case allocated, active, metadata
        case metadataThp = "metadata_thp"
        case resident, mapped, retained
        case zeroReallocs = "zero_reallocs"
        case backgroundThread = "background_thread"
        case mutexes
    }
}

// MARK: - StatsBackgroundThread

struct StatsBackgroundThread: Codable {
    let numThreads, numRuns, runInterval: Int

    enum CodingKeys: String, CodingKey {
        case numThreads = "num_threads"
        case numRuns = "num_runs"
        case runInterval = "run_interval"
    }
}

// MARK: - Mutexes

struct Mutexes: Codable {
    let backgroundThread, maxPerBgThd, ctl, prof: BackgroundThreadValue
    let profThdsData, profDump, profRecentAlloc, profRecentDump: BackgroundThreadValue
    let profStats: BackgroundThreadValue

    enum CodingKeys: String, CodingKey {
        case backgroundThread = "background_thread"
        case maxPerBgThd = "max_per_bg_thd"
        case ctl, prof
        case profThdsData = "prof_thds_data"
        case profDump = "prof_dump"
        case profRecentAlloc = "prof_recent_alloc"
        case profRecentDump = "prof_recent_dump"
        case profStats = "prof_stats"
    }
}

// MARK: - BackgroundThreadValue

struct BackgroundThreadValue: Codable {
    let numOps, numWait, numSpinAcq, numOwnerSwitch: Int
    let totalWaitTime, maxWaitTime, maxNumThds: Int

    enum CodingKeys: String, CodingKey {
        case numOps = "num_ops"
        case numWait = "num_wait"
        case numSpinAcq = "num_spin_acq"
        case numOwnerSwitch = "num_owner_switch"
        case totalWaitTime = "total_wait_time"
        case maxWaitTime = "max_wait_time"
        case maxNumThds = "max_num_thds"
    }
}

// MARK: - StatsArenas

struct StatsArenas: Codable {
    let merged: Merged
}

// MARK: - Merged

struct Merged: Codable {
    let nthreads, uptimeNS: Int
    let dss: String
    let dirtyDecayMS, muzzyDecayMS, pactive, pdirty: Int
    let pmuzzy, dirtyNpurge, dirtyNmadvise, dirtyPurged: Int
    let muzzyNpurge, muzzyNmadvise, muzzyPurged: Int
    let small, large: Large
    let mapped, retained, base, mergedInternal: Int
    let metadataThp, tcacheBytes, tcacheStashedBytes, resident: Int
    let abandonedVM, extentAvail: Int
    let mutexes: [String: BackgroundThreadValue]
    let bins: [MergedBin]
    let lextents: [MergedLextent]
    let extents: [Extent]
    let secBytes: Int
    let hpaShard: HpaShard

    enum CodingKeys: String, CodingKey {
        case nthreads
        case uptimeNS = "uptime_ns"
        case dss
        case dirtyDecayMS = "dirty_decay_ms"
        case muzzyDecayMS = "muzzy_decay_ms"
        case pactive, pdirty, pmuzzy
        case dirtyNpurge = "dirty_npurge"
        case dirtyNmadvise = "dirty_nmadvise"
        case dirtyPurged = "dirty_purged"
        case muzzyNpurge = "muzzy_npurge"
        case muzzyNmadvise = "muzzy_nmadvise"
        case muzzyPurged = "muzzy_purged"
        case small, large, mapped, retained, base
        case mergedInternal = "internal"
        case metadataThp = "metadata_thp"
        case tcacheBytes = "tcache_bytes"
        case tcacheStashedBytes = "tcache_stashed_bytes"
        case resident
        case abandonedVM = "abandoned_vm"
        case extentAvail = "extent_avail"
        case mutexes, bins, lextents, extents
        case secBytes = "sec_bytes"
        case hpaShard = "hpa_shard"
    }
}

// MARK: - MergedBin

struct MergedBin: Codable {
    let nmalloc, ndalloc, curregs, nrequests: Int
    let nfills, nflushes, nreslabs, curslabs: Int
    let nonfullSlabs: Int
    let mutex: BackgroundThreadValue

    enum CodingKeys: String, CodingKey {
        case nmalloc, ndalloc, curregs, nrequests, nfills, nflushes, nreslabs, curslabs
        case nonfullSlabs = "nonfull_slabs"
        case mutex
    }
}

// MARK: - Extent

struct Extent: Codable {
    let ndirty, nmuzzy, nretained, dirtyBytes: Int
    let muzzyBytes, retainedBytes: Int

    enum CodingKeys: String, CodingKey {
        case ndirty, nmuzzy, nretained
        case dirtyBytes = "dirty_bytes"
        case muzzyBytes = "muzzy_bytes"
        case retainedBytes = "retained_bytes"
    }
}

// MARK: - HpaShard

struct HpaShard: Codable {
    let npurgePasses, npurges, nhugifies, ndehugifies: Int
    let fullSlabs, emptySlabs: EmptySlabs
    let nonfullSlabs: [EmptySlabs]

    enum CodingKeys: String, CodingKey {
        case npurgePasses = "npurge_passes"
        case npurges, nhugifies, ndehugifies
        case fullSlabs = "full_slabs"
        case emptySlabs = "empty_slabs"
        case nonfullSlabs = "nonfull_slabs"
    }
}

// MARK: - EmptySlabs

struct EmptySlabs: Codable {
    let npageslabsHuge, nactiveHuge, npageslabsNonhuge, nactiveNonhuge: Int
    let ndirtyNonhuge: Int
    let ndirtyHuge: Int?

    enum CodingKeys: String, CodingKey {
        case npageslabsHuge = "npageslabs_huge"
        case nactiveHuge = "nactive_huge"
        case npageslabsNonhuge = "npageslabs_nonhuge"
        case nactiveNonhuge = "nactive_nonhuge"
        case ndirtyNonhuge = "ndirty_nonhuge"
        case ndirtyHuge = "ndirty_huge"
    }
}

// MARK: - Large

struct Large: Codable {
    let allocated, nmalloc, ndalloc, nrequests: Int
    let nfills, nflushes: Int
}

// MARK: - MergedLextent

struct MergedLextent: Codable {
    let curlextents: Int
}

// swiftlint:enable all

#endif
