#' Postprocessing: decompress zip, gz, bz2, Z files and optionally delete the compressed copy
#'
#' Functions for decompressing files after downloading. These functions are not intended to be called directly, but rather are specified as a \code{postprocess} option in \code{\link{bb_source}}. \code{bb_unzip}, \code{bb_gunzip}, \code{bb_bunzip2}, and \code{bb_uncompress} are convenience wrappers around \code{bb_decompress} that specify the method.
#'
#' If the data source delivers compressed files, you will most likely want to decompress them after downloading. These functions will do this for you. By default, these do not delete the compressed files after decompressing. The reason for this is so that on the next synchronization run, the local (compressed) copy can be compared to the remote compressed copy, and the download can be skipped if nothing has changed. Deleting local compressed files will save space on your file system, but may result in every file being re-downloaded on every synchronization run.
#'
#' @param method string: one of "unzip","gunzip","bunzip2","decompress"
#' @param delete logical: delete the zip files after extracting their contents?
#' @param ... : extra parameters passed automatically by \code{bb_sync}
#'
#' @return TRUE on success
#'
#' @seealso \code{\link{bb_source}}, \code{\link{bb_config}}, \code{\link{bb_cleanup}}
#' @examples
#' \dontrun{
#'   ## decompress .zip files after synchronization but keep zip files intact
#'   my_source <- bb_source(...,postprocess=list("bb_unzip"))
#'
#'   ## decompress .zip files after synchronization and delete zip files
#'   my_source <- bb_source(...,postprocess=list(list("bb_unzip",delete=TRUE)))
#' }
#'
#' @export
bb_decompress <- function(method,delete=FALSE,...) {
    assert_that(is.flag(delete),!is.na(delete))
    assert_that(is.string(method))
    method <- match.arg(tolower(method),c("unzip","gunzip","bunzip2","uncompress"))
    do.call(bb_decompress_inner,list(...,method=method,delete=delete))
}


# @param config bb_config: a bowerbird configuration (as returned by \code{bb_config}) with a single data source
# @param file_list_before data.frame: files present in the directory before synchronizing, as returned by \code{file.info}. (This is not required if \code{delete} is TRUE)
# @param file_list_after data.frame: files present in the directory after synchronizing, as returned by \code{file.info}. (This is not required if \code{delete} is TRUE)
# @param verbose logical: if TRUE, provide additional progress output
# @param method string: one of "unzip","gunzip","bunzip2","decompress"
# @param delete logical: delete the zip files after extracting their contents?
# @param ... : parameters passed to bb_decompress
#
# @return TRUE on success
bb_decompress_inner <- function(config,file_list_before,file_list_after,verbose=FALSE,method,delete=FALSE) {
    assert_that(is(config,"bb_config"))
    assert_that(nrow(bb_data_sources(config))==1)
    assert_that(is.flag(delete),!is.na(delete))
    assert_that(is.string(method))
    method <- match.arg(tolower(method),c("unzip","gunzip","bunzip2","uncompress"))
    ignore_case <- method=="unzip"
    file_pattern <- switch(method,
                           "unzip"="\\.zip$",
                           "gunzip"="\\.gz$",
                           "bunzip2"="\\.bz2$",
                           "uncompress"="\\.Z$",
                           stop("unrecognized decompression")
                           )
    if (delete) {
        files_to_decompress <- list.files(directory_from_url(bb_data_sources(config)$source_url),pattern=file_pattern,recursive=TRUE,ignore.case=ignore_case)
        do_decompress_files(paste0(method,"_delete"),files=files_to_decompress,verbose=verbose)
    } else {
        ## decompress but retain compressed file. decompress only if .zip/.gz/.bz2/.Z file has changed
        files_to_decompress <- find_changed_files(file_list_before,file_list_after,file_pattern)
        do_decompress_files(method,files=files_to_decompress,verbose=verbose)
        ## also decompress if uncompressed file does not exist
        files_to_decompress <- setdiff(rownames(file_list_after),files_to_decompress) ## those that we haven't just dealt with
        files_to_decompress <- files_to_decompress[str_detect(files_to_decompress,regex(file_pattern,ignore_case=ignore_case))] ## only .zip/.gz/.bz2/.Z files
        do_decompress_files(method,files=files_to_decompress,overwrite=FALSE,verbose=verbose)
        ## nb this may be slow, so might be worth explicitly checking for the existence of uncompressed files
    }
}

## internal function
do_decompress_files <- function(method,files,overwrite=TRUE,verbose=FALSE) {
    ## decompress (unzip/gunzip) compressed files
    ## this function overwrites existing decompressed files if overwrite is TRUE
    assert_that(is.string(method))
    method <- match.arg(method,c("unzip","unzip_delete","gunzip","gunzip_delete","bunzip2","bunzip2_delete","uncompress","uncompress_delete"))
    if (grepl("uncompress",method)) {
        ## uncompress uses archive::file_read, which is a suggested package
        ## check that we have it
        if (!requireNamespace("archive",quietly=TRUE))
            stop("the archive package is needed for uncompress functionality")

    }
    ## unzip() issues warnings in some cases when operations have errors, and sometimes issues actual errors
    warn <- getOption("warn") ## save current setting
    options(warn=0) ## so that we can be sure that last.warning will be set
    ## MDS: this should use tail(warnings(), 1) instead
    last.warning <- NULL ## to avoid check note
    all_OK <- TRUE
    for (thisf in files) {
        ## decompress, check for errors in doing so
        if (verbose) cat(sprintf("  decompressing: %s ... ",thisf))
        switch(method,
               "unzip_delete"=,
               "unzip"={
                   was_ok <- FALSE
                   suppressWarnings(warning("")) ## clear last.warning message
                   ## unzip will put files in the current directory by default, so we need to extract the target directory for this file
                   target_dir <- dirname(thisf)
                   tryCatch({ unzipped_files <- unzip(thisf,list=TRUE) ## get list of files in archive
                              files_to_extract <- unzipped_files$Name
                              if (!overwrite) {
                                  ## extract only files that don't exist
                                  files_to_extract<-files_to_extract[!file.exists(file.path(target_dir,files_to_extract))]
                              }
                              if (length(files_to_extract)>0) {
                                  if (verbose) cat(sprintf('extracting %d files into %s ... ',length(files_to_extract),target_dir))
                                  unzip(thisf,files=files_to_extract,exdir=target_dir) ## now actually unzip them
                                  was_ok <- is.null(last.warning[[1]]) && all(file.info(files_to_extract)$size>0)
                              } else {
                                  if (verbose) cat(sprintf('no new files to extract (not overwriting existing files) ... '))
                                  was_ok <- TRUE
                              }
                              if (verbose) cat("done.\n")
                          },
                            error=function(e) {
                                ## an error here might be because of an incompletely-downloaded file. Is there something more sensible to do in this case?
                                ## but don't treat as a full blown error, since we'll want to proceed with the remaining zip files
                                if (verbose) cat(sprintf("  %s failed to unzip (it may be incompletely-downloaded?)\n Error message was: %s",thisf,e))
                            })
                   if (identical(method,"unzip_delete")) {
                       ## if all looks OK, delete zipped file
                       if (was_ok) {
                           if (verbose) cat(sprintf("  unzip of %s appears OK, deleting\n",thisf))
                           unlink(thisf)
                       } else {
                           if (verbose) cat(sprintf("  problem unzipping %s, not deleting\n",thisf))
                       }
                   }
                   all_OK <- all_OK && was_ok
               },
               "gunzip_delete"=,
               "gunzip"={
                   ## gunzip takes care of deleting the compressed file if remove is TRUE
                   unzip_this <- TRUE
                   was_ok <- FALSE
                   if (!overwrite) {
                       ## check if file exists, so that we can issue a more informative trace message to the user
                       destname <- gsub("[.]gz$","",thisf,ignore.case=TRUE)
                       if (file.exists(destname)) {
                           if (verbose) cat(sprintf(" uncompressed file exists, skipping ... "))
                           unzip_this <- FALSE
                       }
                   }
                   if (unzip_this) {
                       ## wrap this in tryCatch block so that errors do not halt our whole process
                       tryCatch({gunzip(thisf,destname=sub("\\.gz$","",thisf),remove=method=="gunzip_delete",overwrite=overwrite); was_ok <- TRUE},
                                error=function(e){
                                    if (verbose) cat(sprintf("  problem gunzipping %s: %s",thisf,e))
                                }
                                )
                   }
                   all_OK <- all_OK && was_ok
                   if (verbose) cat(sprintf("done\n"))
               },
               "bunzip2_delete"=,
               "bunzip2"={
                   ## same as for gunzip
                   unzip_this <- TRUE
                   was_ok <- FALSE
                   if (!overwrite) {
                       ## check if file exists, so that we can issue a more informative trace message to the user
                       destname <- gsub("[.]bz2$","",thisf,ignore.case=TRUE)
                       if (file.exists(destname)) {
                           if (verbose) cat(sprintf(" uncompressed file exists, skipping ... "))
                           unzip_this <- FALSE
                       }
                   }
                   if (unzip_this) {
                       ## wrap this in tryCatch block so that errors do not halt our whole process
                       tryCatch({bunzip2(thisf,destname=sub("\\.bz2$","",thisf),remove=method=="bunzip2_delete",overwrite=overwrite);was_ok <- TRUE},
                                error=function(e){
                                    if (verbose) cat(sprintf("  problem bunzipping %s: %s",thisf,e))
                                }
                                )
                   }
                   all_OK <- all_OK && was_ok
                   if (verbose) cat(sprintf("done\n"))
               },
               "uncompress_delete"=,
               "uncompress"={
                   unzip_this <- TRUE
                   was_ok <- FALSE
                   destname <- gsub("\\.Z$","",thisf,ignore.case=TRUE)
                   if (!overwrite) {
                       ## check if file exists, so that we can issue a more informative trace message to the user
                       if (file.exists(destname)) {
                           if (verbose) cat(sprintf(" uncompressed file exists, skipping ... "))
                           unzip_this <- FALSE
                       }
                   }
                   if (unzip_this) {
                       ## wrap this in tryCatch block so that errors do not halt our whole process
                       tryCatch({
                           fsize <- 1e7 ## needs to be the UNCOMPRESSED size, which is around 850k elements. Is allowed to be an overestimate, but the written file will be corrupt if this is an underestimate
                           ff <- archive::file_read(thisf)
                           open(ff,"rb") ## open in binary mode, so that readBin is happy
                           writeBin(readBin(ff,"raw",fsize),destname)
                           close(ff)
                           if (grepl("delete",method)) file.remove(thisf)
                           was_ok <- TRUE
                       },
                       error=function(e){
                           if (verbose) cat(sprintf("  problem uncompressing %s: %s",thisf,e))
                       })
                   }
                   all_OK <- all_OK && was_ok
                   if (verbose) cat(sprintf("done\n"))
               },
               stop("unsupported decompress method ",method)
               )
    }
    options(warn=warn) ## reset
    all_OK
}

## internal function
find_changed_files <- function(file_list_before,file_list_after,filename_pattern=".*") {
    ## expect both file_list_before and file_list_after to be a data.frame from file.info()
    ## detect changes on basis of ctime and size attributes
    ## returns names only
    changed_files <- setdiff(rownames(file_list_after),rownames(file_list_before)) ## anything that has appeared afterwards
    for (thisf in intersect(rownames(file_list_after),rownames(file_list_before))) {
        ## files in both
        thisfile_after <- file_list_after[rownames(file_list_after)==thisf,]
        thisfile_before <- file_list_before[rownames(file_list_before)==thisf,]
        if ((thisfile_after$ctime>thisfile_before$ctime) | (thisfile_after$size!=thisfile_before$size)) {
            changed_files <- c(changed_files,thisf)
        }
    }
    changed_files <- changed_files[str_detect(changed_files,filename_pattern)]
    if (is.null(changed_files)) {
        c()
    } else {
        changed_files
    }
}


#' @rdname bb_decompress
#' @export
bb_unzip <- function(...) bb_decompress(...,method="unzip")

#' @rdname bb_decompress
#' @export
bb_gunzip <- function(...) bb_decompress(...,method="gunzip")

#' @rdname bb_decompress
#' @export
bb_bunzip2 <- function(...) bb_decompress(...,method="bunzip2")

#' @rdname bb_decompress
#' @export
bb_uncompress <- function(...) bb_decompress(...,method="uncompress")


#' Postprocessing: remove unwanted files
#'
#' A function for removing unwanted files after downloading. This function is not intended to be called directly, but rather is specified as a \code{postprocess} option in \code{\link{bb_source}}.
#'
#' This function can be used to remove unwanted files after a data source has been synchronized. The \code{pattern} specifies a regular expression that is passed to \code{file.info} to find matching files, which are then deleted. Note that only files in the data source's own directory (i.e. its subdirectory of the \code{local_file_root} specified in \code{bb_config}) are subject to deletion. But, beware! Some data sources may share directories, which can lead to unexpected file deletion. Be as specific as you can with the \code{pattern} parameter.
#'
#' @param pattern string: regular expression, passed to \code{file.info}
#' @param recursive logical: should the cleanup recurse into subdirectories?
#' @param ignore_case logical: should pattern matching be case-insensitive?
#' @param ... : extra parameters passed automatically by \code{bb_sync}
#'
#' @return TRUE on success
#'
#' @seealso \code{\link{bb_source}}, \code{\link{bb_config}}, \code{\link{bb_decompress}}
#'
#' @examples
#' \dontrun{
#'   ## remove .asc files after synchronization
#'   my_source <- bb_source(...,postprocess=list(list("bb_cleanup",pattern="\\.asc$")))
#' }
#'
#' @export
bb_cleanup <- function(pattern,recursive=FALSE,ignore_case=FALSE,...) {
    assert_that(is.string(pattern))
    assert_that(is.flag(recursive),!is.na(recursive))
    assert_that(is.flag(ignore_case),!is.na(ignore_case))
    do.call(bb_cleanup_inner,list(...,pattern=pattern,recursive=recursive,ignore_case=ignore_case))
}


# @param config bb_config: a bowerbird configuration (as returned by \code{bb_config}) with a single data source
# @param file_list_before data.frame: files present in the directory before synchronizing, as returned by \code{file.info}
# @param file_list_after data.frame: files present in the directory after synchronizing, as returned by \code{file.info}
# @param verbose logical: if TRUE, provide additional progress output
# @param pattern string: regular expression, passed to \code{file.info}
# @param recursive logical: should the cleanup recurse into subdirectories?
# @param ignore_case logical: should pattern matching be case-insensitive?
#
# @return TRUE on success
#
bb_cleanup_inner <- function(config,file_list_before,file_list_after,verbose=FALSE,pattern,recursive=FALSE,ignore_case=FALSE) {
    assert_that(is(config,"bb_config"))
    assert_that(nrow(bb_data_sources(config))==1)
    to_delete <- list.files(path=bb_data_source_dir(config),pattern=pattern,recursive=recursive,ignore.case=ignore_case,full.names=TRUE)
    if (verbose) {
        if (length(to_delete)>0) {
            if (verbose) cat(sprintf(" cleaning up files: %s\n",paste(to_delete,collapse=",")))
        } else {
            if (verbose) cat(" cleanup: no files to remove\n")
        }
    }
    unlink(to_delete)==0
}
