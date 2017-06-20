context("sync")

test_that("bb_sync works",{
    skip("skipping bb_sync test temporarily") ## during dev
    ods <- bb_source(
        name="Oceandata test",
        description="Monthly remote-sensing sea surface temperature from the MODIS Terra satellite at 9km spatial resolution",
        reference= "http://oceancolor.gsfc.nasa.gov/",
        citation="See http://oceancolor.gsfc.nasa.gov/cms/citations",
        source_url="",
        license="Please cite",
        comment="",
        method=oceandata_get,
        method_flags="search=T20000322000060.L3m_MO_SST_sst_9km.nc",
        postprocess=NULL,
        access_function="",
        data_group="Sea surface temperature")
    temp_root <- tempdir()
    ocf <- add(bb_config(local_file_root=temp_root),ods)
    bb_sync(ocf)
    
    fnm <- file.path(temp_root,"oceandata.sci.gsfc.nasa.gov/MODIST/Mapped/Monthly/9km/SST/T20000322000060.L3m_MO_SST_sst_9km.nc")
    expect_true(file.exists(fnm))
    fi <- file.info(fnm)
    expect_gt(fi$size,6e6)
})