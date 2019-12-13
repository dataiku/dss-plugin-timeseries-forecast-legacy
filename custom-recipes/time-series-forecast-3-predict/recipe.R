##### LIBRARY LOADING #####

library(dataiku)
source(file.path(dkuCustomRecipeResource(), "predict.R"))


##### INPUT OUTPUT CONFIGURATION #####

MODEL_FOLDER_NAME <- dkuCustomRecipeInputNamesForRole('MODEL_FOLDER_NAME')[1]
EVALUATION_DATASET_NAME <- dkuCustomRecipeInputNamesForRole('EVALUATION_DATASET_NAME')[1]
FUTURE_XREG_DATASET_NAME <- dkuCustomRecipeInputNamesForRole('FUTURE_XREG_DATASET_NAME')[1]
OUTPUT_DATASET_NAME <- dkuCustomRecipeOutputNamesForRole('OUTPUT_DATASET_NAME')[1]

config <- dkuCustomRecipeConfig()
for(n in names(config)) {
  config[[n]] <- CleanPluginParam(config[[n]])
}
if (!config[["INCLUDE_FORECAST"]] && !config[["INCLUDE_HISTORY"]]) {
  PrintPlugin("Please include either forecast and/or history", stop = TRUE)
}

# Check that partitioning settings are correct if activated
checkPartitioning <- CheckPartitioningSettings(EVALUATION_DATASET_NAME)

# Loads all forecasting objects from the model folder
LoadForecastingObjects(MODEL_FOLDER_NAME)


##### MODEL SELECTION #####

PrintPlugin("Model selection stage")

if (config[["MODEL_SELECTION"]] == "auto") {
  evalDf <- dkuReadDataset(EVALUATION_DATASET_NAME, columns = c("model", config[["ERROR_METRIC"]]))
  config[["SELECTED_MODEL"]] <- evalDf[[which.min(evalDf[[config[["ERROR_METRIC"]]]]), "model"]] %>%
    recode(!!!MODEL_UI_NAME_LIST_REV)
}

PrintPlugin(paste0("Model selection stage completed: ", config[["SELECTED_MODEL"]], " selected."))


##### FORECASTING STAGE #####

PrintPlugin("Forecasting stage")

externalRegressorMatrix <- NULL
if (!is.na(FUTURE_XREG_DATASET_NAME)) {
  if (is.null(configTrain[["EXT_SERIES_COLUMNS"]]) ||
     length(configTrain[["EXT_SERIES_COLUMNS"]]) == 0 ||
      is.na(configTrain[["EXT_SERIES_COLUMNS"]])) {
    PrintPlugin("Future external regressors dataset provided but no external regressors \
                were provided at training time. Please re-run the Train and Evaluate recipe \
                with external regressors specified in the recipe settings.", stop = TRUE)
  }
  PrintPlugin("Including the future values of external regressors")
  selectedColumns <- c(configTrain[["TIME_COLUMN"]], configTrain[["EXT_SERIES_COLUMNS"]])
  columnClasses <- c("character", rep("numeric", length(configTrain[["EXT_SERIES_COLUMNS"]])))
  dfXreg <- dkuReadDataset(FUTURE_XREG_DATASET_NAME,
    columns = selectedColumns, colClasses = columnClasses)

   # Fix case of invalid column names in input
  names(dfXreg) <- str_replace_all(names(dfXreg), '[^a-zA-Z0-9]', "_")
  configTrain[["TIME_COLUMN"]] <- names(dfXreg)[1]
  configTrain[["EXT_SERIES_COLUMNS"]] <- names(dfXreg)[2:ncol(dfXreg)]

  dfXreg <- dfXreg %>% PrepareDataframeWithTimeSeries(
    configTrain[["TIME_COLUMN"]], configTrain[["EXT_SERIES_COLUMNS"]],
    configTrain[["GRANULARITY"]], configTrain[["AGGREGATION_STRATEGY"]], resample = FALSE)
  config[["FORECAST_HORIZON"]] <- nrow(dfXreg)
  externalRegressorMatrix <- as.matrix(dfXreg[configTrain[["EXT_SERIES_COLUMNS"]]])
  colnames(externalRegressorMatrix) <- configTrain[["EXT_SERIES_COLUMNS"]]
} else {
  if(length(configTrain[["EXT_SERIES_COLUMNS"]]) != 0) {
    PrintPlugin("External regressors were used at training time but \
                no dataset for future values of regressors has been provided. \
                Please add the dataset for future values in the Input / Output tab of the recipe. \
                If no future values are availables, please re-run the Train and Evaluate recipe \
                without external regressors", stop = TRUE)
  }
}

forecastDfList <- GetForecasts(
  ts, df, externalRegressorMatrix,
  modelList[config[["SELECTED_MODEL"]]],
  modelParameterList[config[["SELECTED_MODEL"]]],
  config[["FORECAST_HORIZON"]],
  configTrain[["GRANULARITY"]],
  config[["CONFIDENCE_INTERVAL"]],
  config[["INCLUDE_HISTORY"]]
)

forecastDf <- forecastDfList[[config[["SELECTED_MODEL"]]]]

dfOutput <- CombineForecastHistory(df[c("ds", "y")], forecastDf,
  config[["INCLUDE_FORECAST"]], config[["INCLUDE_HISTORY"]])
dfOutput[["selected_model"]] <- recode(config[["SELECTED_MODEL"]], !!!MODEL_UI_NAME_LIST)

# Keep external regressor columns if any
if(nrow(dfXreg) != 0) {
  originaldfXreg <- df[c("ds", configTrain[["EXT_SERIES_COLUMNS"]])]
  names(dfXreg) <- c('ds', config[["EXT_SERIES_COLUMNS"]])
  print(colnames(originaldfXreg))
  print(colnames(dfXreg))
  dfXregStacked <- rbind(originaldfXreg, dfXreg)
  dfOutput <- merge(x = dfOutput, y = dfXregStacked, by = "ds", all.x = TRUE)
}

# Standardises column names
names(dfOutput) <- dplyr::recode(
  .x = names(dfOutput),
  ds = configTrain[["TIME_COLUMN"]],
  y = configTrain[["SERIES_COLUMN"]],
  yhat = "forecast",
  yhat_lower = "forecast_lower_confidence_interval",
  yhat_upper = "forecast_upper_confidence_interval",
  residuals = "forecast_residuals"
)

# converts the date from POSIX to a character following dataiku date format in ISO 8601 standard
dfOutput[[configTrain[["TIME_COLUMN"]]]] <- strftime(dfOutput[[configTrain[["TIME_COLUMN"]]]] , dkuDateFormat)

# # removes the unnecessary floor and cap columns from prophet model if they exist
# dfOutput <- dfOutput %>%
#   select(-one_of(c("floor", "cap")))

PrintPlugin("Forecasting stage completed, saving forecasts to output dataset.")

WriteDatasetWithPartitioningColumn(dfOutput, OUTPUT_DATASET_NAME)

PrintPlugin("All stages completed!")
