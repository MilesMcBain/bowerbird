#' Postprocessing: decompress zip, gz, bz2, Z files and optionally delete the compressed copy
#' \code{pp_unzip}, \code{pp_gunzip}, \code{pp_bunzip2}, and \code{pp_uncompress} are convenience wrappers around \code{pp_decompress} that specify the method.
#' The dots argument indicates additional arguments that are passed to \code{pp_decompress}. Some may be passed by \code{bb_sync}. These include parameters named \code{file_list_before} and \code{file_list_after}, which are data.frames as returned by \code{file.info}, listing the files present in the target directory before and after synchronising. These are used if delete=TRUE.
#'
#' @param data_source tibble: single-row tibble defining a data source, e.g. as returned by \code{bb_source}
#' @param delete logical: delete the zip files after extracting their contents?
#' @param method string: one of "unzip","gunzip","bunzip2","decompress"
#' @param ... : additional arguments passed to \code{pp_decompress}
#'
#' @return TRUE on success
#'
#' @seealso \code{\link{bb_source}} \code{\link{bb_config}} \code{\link{pp_cleanup}}
#'
#' @examples
#'
#' @export
pp_decompress <- function(data_source,delete=FALSE,method,...){##file_list_before,file_list_after,method) {
    assert_that(is.data.frame(data_source))
    assert_that(nrow(data_source)==1)
    assert_that(is.flag(delete))
    assert_that(is.string(method))
    method <- match.arg(tolower(method),c("unzip","gunzip","bunzip2","uncompress"))
    xargs <- list(...)
    if (method=="unzip") {
        if (delete) {
            files_to_decompress <- list.files(directory_from_url(data_source$source_url),pattern="\\.zip$",recursive=TRUE,ignore.case=TRUE)
            do_decompress_files("unzip_delete",files=files_to_decompress)
        } else {
            ## decompress but retain compressed file
            file_list_before <- extract_xarg("file_list_before",xargs)
            file_list_after <- extract_xarg("file_list_after",xargs)
            ## since the zip file will have been retained from previous runs, decompress only if the zip file has changed
            files_to_decompress <- find_changed_files(file_list_before,file_list_after,"\\.zip$")
            do_decompress_files("unzip",files=files_to_decompress)
            ## also decompress any files present in the zip file that don't exist in decompressed form
            files_to_decompress <- setdiff(rownames(file_list_after),files_to_decompress) ## those that we haven't just dealt with
            files_to_decompress <- files_to_decompress[str_detect(files_to_decompress,regex("\\.zip$",ignore_case=TRUE))] ## only zip files
            do_decompress_files("unzip",files=files_to_decompress,overwrite=FALSE)
        }
    } else {
        file_pattern <- switch(method,
                               "gunzip"="\\.gz$",
                               "bunzip2"="\\.bz2$",
                               "uncompress"="\\.Z$",
                               stop("unrecognized decompression")
                               )
        if (delete) {
            ## unconditionally unzip then delete
            files_to_decompress <- list.files(directory_from_url(data_source$source_url),pattern=file_pattern,recursive=TRUE)
            do_decompress_files(paste0(method,"_delete"),files=files_to_decompress)
        } else {
            file_list_before <- extract_xarg("file_list_before",xargs)
            file_list_after <- extract_xarg("file_list_after",xargs)
            ## decompress but retain compressed file. decompress only if .gz/.bz2/.Z file has changed
            files_to_decompress <- find_changed_files(file_list_before,file_list_after,file_pattern)
            do_decompress_files(method,files=files_to_decompress)
            ## also decompress if uncompressed file does not exist
            files_to_decompress <- setdiff(rownames(file_list_after),files_to_decompress) ## those that we haven't just dealt with
            files_to_decompress <- files_to_decompress[str_detect(files_to_decompress,file_pattern)] ## only .gz/.bz2/.Z files
            do_decompress_files(method,files=files_to_decompress,overwrite=FALSE)
            ## nb this may be slow, so might be worth explicitly checking for the existence of uncompressed files
        }
    }
}
# @param file_list_before data.frame: files present in the directory before synchronising, as returned by \code{file.info}. Only required if delete=TRUE
# @param file_list_after data.frame: files present in the directory after synchronising, as returned by \code{file.info}. Only required if delete=TRUE
# @param ... : arguments passed to \code{pp_decompress}


## decompression behaviour: for *_delete, unconditionally decompress all compressed files and then delete them
## for gunzip/bunzip2 (which can only contain a single file), decompress only if .gz/.bz2 file has changed
## for unzip (which can contain multiple files), decompress all if the zip file has changed, or if there are any files present in the zip file that don't exist in decompressed form

extract_xarg <- function(required,xargs) if (required %in% names(xargs)) xargs[[required]] else stop("need ",required," passed as one of the dots arguments")

#' @rdname pp_decompress
#' @export
pp_unzip <- function(...) pp_decompress(...,method="unzip")

#' @rdname pp_decompress
#' @export
pp_gunzip <- function(...) pp_decompress(...,method="gunzip")

#' @rdname pp_decompress
#' @export
pp_bunzip2 <- function(...) pp_decompress(...,method="bunzip2")

#' @rdname pp_decompress
#' @export
pp_uncompress <- function(...) pp_decompress(...,method="uncompress")


#' Postprocessing: remove unwanted files
#'
#' @param data_source tibble: single-row tibble defining a data source, e.g. as returned by \code{bb_source}
#' @param pattern string: regular expression, passed to \code{file.info}
#' @param recursive logical: should the cleanup recurse into subdirectories?
#' @param ignore_case logical: should pattern matching be case-insensitive?
#' @param ... : additional arguments (currently ignored)
#'
#' @return TRUE on success
#'
#' @seealso \code{\link{bb_source}} \code{\link{bb_config}} \code{\link{pp_decompress}}
#'
#' @examples
#' \dontrun{
#'   ## remove .asc files after synchronisation
#'   my_source <- bb_source(...,postprocess=list(quote(pp_cleanup,pattern="\\.asc$")))
#' }
#'
#' @export
pp_cleanup <- function(data_source,pattern,recursive=FALSE,ignore_case=FALSE,...) {
    assert_that(is.data.frame(data_source))
    assert_that(nrow(data_source)==1)
    to_delete <- list.files(pattern=pattern,recursive=recursive,ignore.case=ignore_case)
    cat(sprintf("cleaning up files: %s\n",paste(to_delete,collapse=",")))
    unlink(to_delete)==0
}


# Postprocessing: unzip files, and optionally delete the .zip
#
# @param data_source tibble: single-row tibble defining a data source, e.g. as returned by \code{bb_source}
# @param delete logical: delete the zip files after extracting their contents?
# @param file_list_before data.frame: files present in the directory before synchronising, as returned by \code{file.info}. Only required if delete=TRUE
# @param file_list_after data.frame: files present in the directory after synchronising, as returned by \code{file.info}. Only required if delete=TRUE
#
# @return TRUE on success
#
# @seealso \code{\link{bb_source}} \code{\link{bb_config}} \code{\link{pp_cleanup}}
#
# @examples
# \dontrun{
#   my_source <- bb_source(...,postprocess=pp_unzip) ## unzip without deleting zip files
#   my_source <- bb_source(...,postprocess=quote(pp_unzip,delete=TRUE,file_list_before,file_list_after)) ## unzip and delete zip files
# }
#
# @export
##xpp_unzip <- function(data_source,delete=FALSE,file_list_before,file_list_after) {
##    assert_that(is.flag(delete))
##    ##xargs <- list(...)
##    ## need data_source passed as one of the dots
##    ##check_xarg("data_source",xargs)
##    if (delete) {
##        files_to_decompress <- list.files(directory_from_url(data_source$source_url),pattern="\\.zip$",recursive=TRUE,ignore.case=TRUE)
##        do_decompress_files("unzip_delete",files=files_to_decompress)
##    } else {
##        ## decompress but retain compressed file
##        ## since the zip file will have been retained from previous runs, decompress only if the zip file has changed
##        files_to_decompress <- find_changed_files(file_list_before,file_list_after,"\\.zip$")
##        do_decompress_files("unzip",files=files_to_decompress)
##        ## also decompress any files present in the zip file that don't exist in decompressed form
##        files_to_decompress <- setdiff(rownames(file_list_after),files_to_decompress) ## those that we haven't just dealt with
##        files_to_decompress <- files_to_decompress[str_detect(files_to_decompress,regex("\\.zip$",ignore_case=TRUE))] ## only zip files
##        do_decompress_files("unzip",files=files_to_decompress,overwrite=FALSE)
##    }
##}
