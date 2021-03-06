#' @title De-aggregate the variable in the datatables and create the first mapping file
#'
#' @param study_name Nickname used for this study
#' @param files Vector containing the pathways to the table you want to expand
#' @param destination Pathway to the folder where you want to create the mapping file
#'
#' @return a mapping file (0_map.csv), and a folder (study_tree) with the tree structure of your sandboxes. Also create a hidden file to copy oldmaps (.oldmaps)
#'
#' @description This function extracts informations from .txt.gz files ind dbgap. It will de-agregate the datatables to create one csv file per variable with 2 columns (dbgap_ID and variable_name), and sort them in one folder per datatable. It also creates the first mapping file ("0_map.csv).
#'
#' @author Gregoire Versmee, Laura Versmee
#' @export
#' @import data.table
#' @import parallel
#' @import XML
#' @import rlist
#' @import RCurl

table.expand <- function(study_name, files, destination = getwd())  {

  ### set some pathways
  ## Create the destination folder
  mappath <- paste0(destination, "/", study_name)
  dir.create(mappath, showWarnings = FALSE)

  ## Create the tree folder
  treepath <- paste0(mappath, "/", study_name, "_tree")
  dir.create(treepath, showWarnings = FALSE)

  ## Create the .oldmaps folder
  oldmappath <- paste0(mappath, "/.oldmaps")
  dir.create(paste0(mappath, "/.oldmaps"), showWarnings = FALSE)

  ## Get all the csv files for the given study
  g <- as.vector(sapply(files, function(e) {
    list.files(e, pattern = ".csv", recursive = TRUE, full.names = TRUE)
  }))

  ## copy the original files to a hidden folder
  filespath <- paste0(mappath, "/.files")
  dir.create(filespath, showWarnings = FALSE)
  file.copy(g, paste0(filespath, "/", basename(g)))

  ### Get the number of cores of the instance
  ncores <- getOption("mc.cores", parallel::detectCores())

  ### Read csv files
  mcl <- lapply(g, function(e) {
    t <- data.table::fread(e, colClasses = "character", na.strings = "")
  })
  names(mcl) <- sub(".csv", "", basename(g))

  ### Expand the tables
  mcl2 <- Reduce(function(x, name) {

    ### get the table
    y <- mcl[[name]]

    ### initialize duplicated colums
    dups <- c()

    ### look if a column label is a duplicate
    for (j in 2:ncol(y)) {
      duplicate <- mapply(function (e, f)  {
        d <- which(colnames(e) == colnames(y)[j])

        ### if so, join the 2 columns
        if (length(d) > 0) {
          x[[f]] <- rbind(x[[f]], y[,c(1,j), with = FALSE], fill = TRUE)
          return(j)
        }
      },x, names(x))
      dups <- c(dups, duplicate)
    }

    dups2 <- unique(as.integer(dups[!sapply(dups, is.null)]))
    if (length(dups2) > 0) y2 <- y[,(dups2) := NULL] else y2 <- y
    #if (length(dups2) > 0) y2 <- y[, data.table::`:=`(dups2 = NULL)] else y2 <- y
    if (ncol(y2) < 2) y3 <- NULL else y3 <- y2
    x[[name]] <- y3
    return(x)
  }, names(mcl), init = list())

  ### write the first map
  variable_id <- lapply(mcl2, function(e) return(colnames(e)[-1]))
  variable_id <- unlist(variable_id, use.names = FALSE)
  questionnaire_id <- unlist(mapply(function(e, f) return(rep(f, ncol(e)-1)), mcl2, names(mcl2)))

  e <- mcl2[[1]]
  names(e)
  ncol(e)
  f <- names(mcl2)[1]

  map <- data.frame(cbind(variable_id, questionnaire_id, variable_id, NA, NA, variable_id, questionnaire_id), row.names = NULL)
  map[,c(8:15)] <- NA
  colnames(map) <- c("variable_id", "questionnaire_id", "variable_original_name", "num_or_char", "code_key", "data_label", paste0("sd",1:9))

  #### nead to deal with duplicates
  test <- mapply(function(e, f) {
    f <- f[, ENCOUNTER := seq_len(.N), by = c(colnames(f)[1])]
    #dir.create(e, showWarnings = FALSE)

    lapply(2:(length(colnames(f))-1), function(x) {

      test <- data.table::data.table(cbind(f[,1], f[,..x], f[,"ENCOUNTER"]))
      test <- na.omit(test, 2)
      return(test)
      #data.table::fwrite(test, paste0(e, colnames(f)[x], ".csv"))
    })

  }, paste0(treepath, "/", names(mcl2)[158], "/"), mcl2[158])

  ## Remove empty directories in the tree
  system(paste("find", treepath, "-name .DS_Store -type f -delete"))
  system(paste("find", treepath, "-empty -type d -delete"))

  ## order the map and write it
  map <- map[with(map, order(sd1, sd2, sd3, sd4, sd5, sd6, sd7, sd8, sd9, data_label)),]
  data.table::fwrite(map, paste0(mappath, "/0_map.csv"))

  ## write the dictionnary table
  dict <- data.frame(matrix(ncol = 3))
  colnames(dict) <- c("key", "code", "value")
  data.table::fwrite(dict, paste0(mappath, "/1_dictionnary.csv"))
}
