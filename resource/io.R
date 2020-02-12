library(dataiku)
library(jsonlite)
library(R.utils)
library(stringr)

source(file.path(dkuCustomRecipeResource(), "utils.R"))

# Set number of digits to use when printing Sys.time.
# It is needed to store version name in the model folder at millisecond granularity.
op <- options(digits.secs = 3)

CleanPluginParam <- function(param) {
  # Inters the types of a plugin parameter object.
  # Required to pass objects from a plugin MAP parameter (where everything is character)
  # to R functions which sometime expect numeric or boolean objects.
  #
  # Args:
  #   param: plugin parameter (list element given by dkuCustomRecipeConfig)
  #
  # Returns:
  #   Parameter of inferred type

  if (length(param) >= 1) { # if the parameter has multiple values
    if (!is.null(names(param))) { # if parameter is a MAP
      output <- list()
      for(n in names(param)) {
        output[[n]] <- InferType(param[[n]])
      }
    } else {
        output <- InferType(param)
    }
  } else { # if empty
    output <- list()
  }
  return(output)
}

GetPartitioningDimension <- function() {
  # Gets the partition dimension name from the flow variables for recipe destinations.
  # Stops if there is more than one partitioning dimension.
  #
  # Args:
  #   None
  #
  # Returns:
  #   Partitioning dimension name

  flowVariables <- fromJSON(Sys.getenv("DKUFLOW_VARIABLES")) # not available in notebooks
  partitionDimensionName <- c()
  for (v in names(flowVariables)){
      if (substr(v, 1, 8) == "DKU_DST_"){
          partitionDimensionName <- c(partitionDimensionName, substr(v, 9, nchar(v)))
      }
  }
  if (length(partitionDimensionName) > 1) {
    PrintPlugin("Output must be partitioned by only one discrete dimension", stop = TRUE)
  } else if ("date" %in% partitionDimensionName) {
    PrintPlugin("Date dimension is not supported, please use only one discrete dimension", stop = TRUE)
  } else if (length(partitionDimensionName) == 1){
    partitionDimensionName <- partitionDimensionName[1]
  } else {
    partitionDimensionName <- ''
  }
  return(partitionDimensionName)
}

CheckPartitioningSettings <- function(inputDatasetName) {
  # Checks that partitioning settings are correct in case it is activated.
  #
  # Args:
  #   inputDatasetName: name of the input Dataiku dataset.
  #
  # Returns:
  #   "OK"  when partitioning is activated with correct settings,
  #   "NOK" when settings are incorrect,
  #   "NP"  when no partitioning is used.

  inputIsPartitioned <- dkuListDatasetPartitions(inputDatasetName)[1] != 'NP'
  partitionDimensionName <- GetPartitioningDimension()
  partitioningIsActivated <- partitionDimensionName != ''
  if (inputIsPartitioned && partitioningIsActivated) {
    check <- 'OK'
  } else if (!inputIsPartitioned && !partitioningIsActivated) {
    check <- "NP"
  } else {
    check <- "NOK"
    PrintPlugin("Partitioning should be activated on all input and output", stop = TRUE)
  }
  return(check)
}

WriteDatasetWithPartitioningColumn <- function(df, outputDatasetName) {
  # Writes a data.frame to a Dataiku dataset with a column to store the partition identifier
  # in case partitioning is activated, else writes the dataset without changes.
  # Needed for filesystem partioning when the partition identifier is not in the data itself.
  # It is very useful to have the partition written in the data in order to
  # build charts on the whole dataset. Could be an option in the native dataiku API?
  #
  # Args:
  #   df: data.frame to write
  #   outputDatasetName: name of the output Dataiku dataset.
  #
  # Returns:
  #   Nothing, simply writes dataframe to dataset

  outputFullName <- dataiku:::dku__resolve_smart_name(outputDatasetName) # bug with naming from plugins on DSS 5.0.2
  outputId <- dataiku:::dku__ref_to_name(outputFullName)
  outputDatasetType <- dkuGetDatasetLocationInfo(outputId)[["locationInfoType"]] # only works in DSS 5.0.5 or higher
  partitionDimensionName <- GetPartitioningDimension()
  partitioningIsActivated <- partitionDimensionName != ''
  if (partitioningIsActivated && outputDatasetType != 'SQL') { # Filesystem partitioning
    partitioningColumnName <- paste0("_dku_partition_", partitionDimensionName)
    # writes partition identifier to the dataframe as a new column
    df[[partitioningColumnName]] <- dkuFlowVariable(paste0("DKU_DST_", partitionDimensionName))
    df <- df %>%
      select(partitioningColumnName, everything())
  }
  dkuWriteDataset(df, outputDatasetName)
}

dkuManagedFolderCopyFromLocalWithPartitioning <- function(folderName, source_base_path, partition_id = NULL) {
  # Copies content of a local filesystem directory to a Dataiku Folder.
  # This function is the equivalent of dkuManagedFolderCopyFromLocal with an additional parameter for partitioning.
  # It also solves a bug with unreadable RData files that was fixed in DSS 6.0.1.
  # Later down the line this function may become part of our native R API.
  #
  # Args:
  #   folderName: dataiku folder name.
  #   source_base_path: path in the local filesystem.
  #   partition_id: target partition in the Dataiku Folder (optional).
  #
  # Returns:
  #   Nothing, simply copies the directory

  local_paths <- list.files(source_base_path, recursive = TRUE)
  for (local_path in local_paths) {
    PrintPlugin(paste0("Uploading ", local_path))
    complete_path <- paste0(source_base_path, "/", local_path)
    local_file <- file(complete_path, "rb")
    # data = readBin(local_file, file.info(complete_path)$size) was causing an issue for RData files
    if(!is.null(partition_id)) {
        local_path <- file.path(partition_id, local_path)
    }
    dkuManagedFolderUploadPath(folderName, local_path, local_file)
  }
  PrintPlugin("Done copying directory from local filesystem to Dataiku Folder")
}

dkuManagedFolderCopyToLocalWithPartitioning <- function(folderName, local_base_path, partition_id = NULL) {
  # Copies content of a Dataiku Folder to a local filesystem directory
  # This function is the equivalent of dkuManagedFolderCopyToLocal with an additional parameter for partitioning.
  # Later down the line this function may become part of our native R API.
  #
  # Args:
  #   folderName: dataiku folder name.
  #   local_base_path: target path in the local filesystem.
  #   partition_id: origin partition in the Dataiku Folder (optional).
  #
  # Returns:
  #   Nothing, simply copies the directory

  folder_paths <- dkuManagedFolderPartitionPaths(folderName, partition_id)
  for (folder_path in folder_paths) {
    dir_to_create <- dirname(paste0(local_base_path, folder_path))
    if(!dir.exists(dir_to_create)) {
      dir.create(dir_to_create, recursive = TRUE)
    }
    local_path <- paste0(local_base_path, folder_path)
    local_file <- file(local_path, "wb")
    PrintPlugin(paste0("Copying ", folder_path, " to ", local_path))
    data <- dkuManagedFolderDownloadPath(folderName, folder_path, as = "raw")
    writeBin(data, local_file)
    close(local_file)
  }
  PrintPlugin("Done copying Dataiku Folder to local filesystem")
}

SaveForecastingObjects <- function(folderName, versionName, ...) {
  # Saves forecasting objects to a single Rdata file in an output folder.
  # Creates a standard directory structure folderpath/(partitionid/)versions/models.RData.
  #
  # Args:
  #   folderName: dataiku folder name.
  #   partitionDimensionName: partition dimension name specified in the plugin UI.
  #   checkPartitioning: output of a call to the CheckPartitioningSettings function.
  #   versionName: identifier of the version of the forecasting objects
  #   ...: objects to save to the folder
  #
  # Returns:
  #   Nothing, simply writes RData file to folder

  # saves to a temporary working directory on the local filesystem
  folderPath <- file.path(getwd(), "models")
  versionPath <- file.path(folderPath, "versions", versionName)
  dir.create(versionPath, recursive = TRUE)
  save(...,  file = file.path(versionPath , "models.RData"))

  # syncs RData file to the local filesystem
  outputFolderIsPartitioned <- dkuManagedFolderDirectoryBasedPartitioning(folderName)
  partitionDimensionName <- GetPartitioningDimension()
  partitioningIsActivated <- partitionDimensionName != ''
  if(partitioningIsActivated && outputFolderIsPartitioned) {
    partition_id <- dkuFlowVariable(paste0("DKU_DST_", partitionDimensionName))
    dkuManagedFolderCopyFromLocalWithPartitioning(folderName, folderPath, partition_id)
  } else if (partitioningIsActivated && !outputFolderIsPartitioned) {
    PrintPlugin("Partitioning should be activated on output folder", stop = TRUE)
  } else {
    dkuManagedFolderCopyFromLocalWithPartitioning(folderName, folderPath)
  }
  # removes RData file on the temporary working directory
  unlink(folderPath, recursive=TRUE)
}

LoadForecastingObjects <- function(folderName, versionName = NULL) {
  # Loads forecasting objects from the folder with saved forecasting objects
  # written by the SaveForecastingObjects function.
  #
  # Args:
  #   folderName: dataiku folder name.
  #   partitionDimensionName: partition dimension name specified in the plugin UI.
  #   checkPartitioning: output of a call to the CheckPartitioningSettings function.
  #   versionName: identifier of the version of the forecasting objects.
  #
  # Returns:
  #   Nothing, simply loads RData file from folder to the global R environment

  # saves all versions to a temporary working directory on the local filesystem
  folderPath <- file.path(getwd(), "models")
  inputFolderIsPartitioned <- dkuManagedFolderDirectoryBasedPartitioning(folderName)
  partitionDimensionName <- GetPartitioningDimension()
  partitioningIsActivated <- partitionDimensionName != ''
  if (partitioningIsActivated && inputFolderIsPartitioned) {
    partition_id <- dkuFlowVariable(paste0("DKU_DST_", partitionDimensionName))
    dkuManagedFolderCopyToLocalWithPartitioning(folderName, folderPath, partition_id)
    folderPath <- file.path(folderPath, partition_id) # partition_id is part of path
  } else if (partitioningIsActivated && !inputFolderIsPartitioned) {
    PrintPlugin("Partitioning should be activated on input folder", stop = TRUE)
  } else {
    dkuManagedFolderCopyToLocalWithPartitioning(folderName, folderPath)
  }

  # loads model version from RData file into the R workspace
  if(is.null(versionName)) {
    lastVersionPath <- max(list.dirs(file.path(folderPath, "versions"), recursive = FALSE))
  } else {
    lastVersionPath <- file.path(folderPath, "versions", versionName)
  }
  PrintPlugin(paste0("Loading forecasting objects from path ", lastVersionPath))
  rdataPathList <- list.files(
    path = lastVersionPath,
    pattern = "*.RData",
    full.names = TRUE,
    recursive = TRUE
  )
  if (length(rdataPathList) == 0) {
    PrintPlugin("No Rdata files found in the model folder", stop = TRUE)
  }
  for (rdataPath in rdataPathList) {
    load(rdataPath, envir = .GlobalEnv)
  }
    PrintPlugin("Forecasting models loaded!")
}
