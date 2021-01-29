##### LIBRARY LOADING #####

library(dataiku)
source(file.path(dkuCustomRecipeResource(), "train.R"))
source(file.path(dkuCustomRecipeResource(), "evaluate.R"))


##### INPUT OUTPUT CONFIGURATION #####

INPUT_DATASET_NAME <- dkuCustomRecipeInputNamesForRole('INPUT_DATASET_NAME')[1]
MODEL_FOLDER_NAME <- dkuCustomRecipeOutputNamesForRole('MODEL_FOLDER_NAME')[1]
EVAL_DATASET_NAME <- dkuCustomRecipeOutputNamesForRole('EVALUATION_DATASET_NAME')[1]

config <- dkuCustomRecipeConfig()
for(n in names(config)) {
  config[[n]] <- CleanPluginParam(config[[n]])
}

# Check that partitioning settings are correct if activated
checkPartitioning <- CheckPartitioningSettings(INPUT_DATASET_NAME)

CheckRVersion()

# Insert all raw parameters for models from plugin UI into each model KWARGS parameter.
# This facilitates the generic calling of forecasting functions with
# a flexible number of keyword arguments.

# Naive model method, see train plugin library
config[["NAIVE_MODEL_KWARGS"]][["method"]] <- config[["NAIVE_MODEL_METHOD"]]

# See auto.arima doc in www.rdocumentation.org/packages/forecast/versions/8.4/topics/auto.arima
config[["ARIMA_MODEL_KWARGS"]][["stepwise"]] <- as.logical(as.numeric(config[["ARIMA_MODEL_STEPWISE"]]))

# See ets doc in https://www.rdocumentation.org/packages/forecast/versions/8.4/topics/ets
config[["EXPONENTIALSMOOTHING_MODEL_KWARGS"]][["model"]] <- paste0(
  config[["EXPONENTIALSMOOTHING_MODEL_ERROR_TYPE"]],
  config[["EXPONENTIALSMOOTHING_MODEL_TREND_TYPE"]],
  config[["EXPONENTIALSMOOTHING_MODEL_SEASONALITY_TYPE"]]
)

# See nnetar doc www.rdocumentation.org/packages/forecast/versions/8.4/topics/nnetar
config[["NEURALNETWORK_MODEL_KWARGS"]][["P"]] <- config[["NEURALNETWORK_MODEL_NUMBER_SEASONAL_LAGS"]]
if (config[["NEURALNETWORK_MODEL_NUMBER_NON_SEASONAL_LAGS"]] != -1) {
  config[["NEURALNETWORK_MODEL_KWARGS"]][["p"]] <- config[["NEURALNETWORK_MODEL_NUMBER_NON_SEASONAL_LAGS"]]
}
if (config[["NEURALNETWORK_MODEL_SIZE"]] != -1) {
  config[["NEURALNETWORK_MODEL_KWARGS"]][["size"]] <- config[["NEURALNETWORK_MODEL_SIZE"]]
}

# Bring all model parameters into a standard named list format for all models
modelParameterList <- list()
for(modelName in AVAILABLE_MODEL_NAME_LIST) {
  modelActivated <- config[[paste0(modelName,"_ACTIVATED")]]
  if (modelActivated) {
    modelParameterList[[modelName]] <- MODEL_FUNCTION_NAME_LIST[[modelName]]
    modelParameterList[[modelName]][["kwargs"]] <- as.list(config[[paste0(modelName,"_KWARGS")]])
  }
}
if (length(modelParameterList) == 0) {
  PrintPlugin("Please select at least one model to train.", stop = TRUE)
}

# Handles default options for the cross-validation evaluation strategy
if (config[["CROSSVAL_INITIAL"]] == -1) {
  config[["CROSSVAL_INITIAL"]] <- 10 * config[["EVAL_HORIZON"]]
}
if (config[["CROSSVAL_PERIOD"]] == -1) {
  config[["CROSSVAL_PERIOD"]] <- ceiling(0.5 * config[["EVAL_HORIZON"]])
}


# Reads input dataset
selectedColumns <- c(config[["TIME_COLUMN"]], config[["SERIES_COLUMN"]], config[["EXT_SERIES_COLUMNS"]])
forbiddenExternalColumnNames <- c("ds", "y")
if(length(intersect(config[["EXT_SERIES_COLUMNS"]], forbiddenExternalColumnNames)) != 0) {
  errorMsg <- paste0("Feature columns cannot be named '",
                paste(forbiddenExternalColumnNames, collapse = ", "),
                "', please rename them.")
  PrintPlugin(errorMsg, stop = TRUE)
}
columnClasses <- c("character", rep("numeric", 1 + length(config[["EXT_SERIES_COLUMNS"]])))
df <- dkuReadDataset(INPUT_DATASET_NAME, columns = selectedColumns, colClasses = columnClasses)

# Fix case of invalid column names in input
names(df) <- str_replace_all(names(df), '[^a-zA-Z0-9]', "_")
config[["TIME_COLUMN"]] <- names(df)[1]
config[["SERIES_COLUMNS"]] <- names(df)[2]
if (!(is.null(config[["EXT_SERIES_COLUMNS"]]) ||
    length(config[["EXT_SERIES_COLUMNS"]]) == 0 ||
    is.na(config[["EXT_SERIES_COLUMNS"]]))) {
  config[["EXT_SERIES_COLUMNS"]] <- names(df)[3:ncol(df)]
}

df <- df %>% PrepareDataframeWithTimeSeries(config[["TIME_COLUMN"]],
    c(config[["SERIES_COLUMN"]], config[["EXT_SERIES_COLUMNS"]]),
    config[["GRANULARITY"]])
names(df) <- c('ds','y', config[["EXT_SERIES_COLUMNS"]]) # Converts df to generic prophet-compatible format
# if (config[["PROPHET_MODEL_ACTIVATED"]] && config[["PROPHET_MODEL_GROWTH"]] == 'logistic') {
#   df[['floor']] <- config[["PROPHET_MODEL_MINIMUM"]]
#   df[['cap']] <- config[["PROPHET_MODEL_MAXIMUM"]]
# }

# Check enough values in the train set
if (nrow(df) - config[["EVAL_HORIZON"]] < 4) {
  PrintPlugin(paste("Less than 4 data points to train models during the evaluation phase.",
    "Please decrease the Horizon parameter."), stop = TRUE)
}
# Additional check on the number of rows of the input for the cross-validation evaluation strategy
if (config[["EVAL_STRATEGY"]] == "crossval" && (config[["EVAL_HORIZON"]] + config[["CROSSVAL_INITIAL"]] > nrow(df))) {
  PrintPlugin(paste("Less data than Horizon after initial cross-validation window.",
    "Please decrease Horizon and/or Initial training parameters."), stop = TRUE)
}

# Converts df to msts time series format
ts <- ConvertDataFrameToTimeSeries(df, "ds", "y", config[["GRANULARITY"]])

# Computes external regressor matrix for forecast models
externalRegressorMatrix <- NULL
if(length(config[["EXT_SERIES_COLUMNS"]]) != 0) {
  externalRegressorMatrix <- as.matrix(df[config[["EXT_SERIES_COLUMNS"]]])
  colnames(externalRegressorMatrix) <- config[["EXT_SERIES_COLUMNS"]]
}

##### TRAINING STAGE #####

PrintPlugin("Training stage starting...")

modelList <- TrainForecastingModels(ts, df, externalRegressorMatrix, modelParameterList)
trainingTimes <- modelList[["trainingTimes"]]
modelList <- modelList[names(modelList) %in% AVAILABLE_MODEL_NAME_LIST]

PrintPlugin("Training stage completed, saving models to output folder.")

versionName <- as.character(Sys.time())
configTrain <- config
SaveForecastingObjects(
  folderName = MODEL_FOLDER_NAME,
  versionName = versionName,
  ts, df, externalRegressorMatrix, modelParameterList, modelList, configTrain
)


##### EVALUATION STAGE #####

PrintPlugin(paste0("Evaluation stage starting with ", config[["EVAL_STRATEGY"]], " strategy..."))

errorDf <- EvaluateModels(ts, df, externalRegressorMatrix, modelList, modelParameterList,
  config[["EVAL_STRATEGY"]], config[["EVAL_HORIZON"]],  config[["GRANULARITY"]],
  config[["CROSSVAL_INITIAL"]], config[["CROSSVAL_PERIOD"]], trainingTimes)
errorDf[["training_date"]] <- strftime(versionName, dkuDateFormat)

PrintPlugin("Evaluation stage completed, saving evaluation results to output dataset.")

WriteDatasetWithPartitioningColumn(errorDf, EVAL_DATASET_NAME)

PrintPlugin("All stages completed!")
