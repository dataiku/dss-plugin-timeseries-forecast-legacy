##### LIBRARY LOADING #####

library(dataiku)
source(file.path(dkuCustomRecipeResource(), "clean.R"))


##### INPUT OUTPUT CONFIGURATION #####

INPUT_DATASET_NAME <- dkuCustomRecipeInputNamesForRole('INPUT_DATASET_NAME')[1]
OUTPUT_DATASET_NAME <- dkuCustomRecipeOutputNamesForRole('OUTPUT_DATASET_NAME')[1]

config <- dkuCustomRecipeConfig()
for(n in names(config)) {
  config[[n]] <- CleanPluginParam(config[[n]])
}

# Check that partitioning settings are correct if activated
checkPartitioning <- CheckPartitioningSettings(INPUT_DATASET_NAME)

selectedColumns <- c(config[["TIME_COLUMN"]], config[["SERIES_COLUMNS"]])
columnClasses <- c("character", rep("numeric", length(config[["SERIES_COLUMNS"]])))
dfInput <- dkuReadDataset(INPUT_DATASET_NAME, columns = selectedColumns, colClasses = columnClasses)

# Fix case of invalid column names in input
names(dfInput) <- str_replace_all(names(dfInput), '[^a-zA-Z0-9]', "_")
config[["TIME_COLUMN"]] <- names(dfInput)[1]
config[["SERIES_COLUMNS"]] <- names(dfInput)[2:ncol(dfInput)]

##### DATA PREPARATION STAGE #####

PrintPlugin("Data preparation stage starting...")

dfOutput <- dfInput %>%
  PrepareDataframeWithTimeSeries(config[["TIME_COLUMN"]], config[["SERIES_COLUMNS"]],
    config[["GRANULARITY"]], config[["AGGREGATION_STRATEGY"]]) %>%
  CleanDataframeWithTimeSeries(config[["TIME_COLUMN"]], config[["SERIES_COLUMNS"]],
    config[["GRANULARITY"]], config[["MISSING_VALUES"]],
    config[["MISSING_IMPUTE_WITH"]], config[["MISSING_IMPUTE_CONSTANT"]],
    config[["OUTLIERS"]], config[["OUTLIERS_IMPUTE_WITH"]],
    config[["OUTLIERS_IMPUTE_CONSTANT"]])

PrintPlugin("Data preparation stage completed, saving prepared data to output dataset.")

WriteDatasetWithPartitioningColumn(dfOutput, OUTPUT_DATASET_NAME)

PrintPlugin("All stages completed!")
