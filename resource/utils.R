PrintPlugin <- function(message, verbose = TRUE, stop = FALSE) {
  # Makes it easier to identify custom logging messages from the plugin.
  if (verbose) {
    if (stop) {
      msg <- paste0(
        "###########################################################\n",
        "[PLUGIN ERROR] ", message, "\n",
        "###########################################################"
      )
      cat(msg)
      stop(message)
    } else {
      msg <- paste0("[PLUGIN LOG] ", message)
      message(msg)
    }
  }
}

InferType <- function(x) {
  # Infers the type of a character object and retains its name.
  #
  # Args:
  #   x: atomic character element.
  #
  # Returns:
  #   Object of inferred type
  if (length(x) >  1) {
      return(x) # do not apply inference to vector or list
  } else {
      if (!is.na(suppressWarnings(as.numeric(x)))) {
        xInferred <- as.numeric(x)
      } else if (!is.na(suppressWarnings(as.logical(x)))) {
        xInferred <- as.logical(x)
      } else {
         xInferred <- as.character(x)
      }
      return(xInferred)
  }
}

CheckRVersion <- function() {
  # Makes sure the R version satisfies the plugin requirements
  rVersion <- as.numeric(R.Version()$major) + as.numeric(R.Version()$minor)/10
  if(rVersion < 3.5) {
    PrintPlugin(
      "Please install a more recent R version on your system, at least 3.5. \
      Then follow the steps described in https://doc.dataiku.com/dss/latest/installation/r.html#rebuilding-the-r-environment" ,
      stop = TRUE
    )
  }
}
