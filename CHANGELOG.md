
## Changelog

## [Version 0.5.2](https://github.com/dataiku/dss-plugin-timeseries-forecast-legacy/releases/tag/v0.5.2) - Deprecation release - 2022-08

- ⚠️ The plugin is made deprecated

## [Version 0.5.1](https://github.com/dataiku/dss-plugin-timeseries-forecast-legacy/releases/tag/v0.5.1) - Bugfix release - 2021-02

- Fix the unselectable output folder of recipes

## [Version 0.5.0](https://github.com/dataiku/dss-plugin-timeseries-forecast-legacy/releases/tag/v0.5.0) - Bugfix and legacy release - 2021-02

- Harmonize UX with the [new Forecast plugin](https://www.dataiku.com/product/plugins/timeseries-forecast/)
- Improve error messages
- Mark as legacy

## [Version 0.4.1](https://github.com/dataiku/dss-plugin-timeseries-forecast-legacy/releases/tag/v0.4.1) - Bugfix release - 2020-02

- Small bug fixes for edge cases

## [Version 0.4.0](https://github.com/dataiku/dss-plugin-timeseries-forecast-legacy/releases/tag/v0.4.0) - New features - 2019-12

- **Kubernetes** and external filesystem support for model storage
- Keep external regressors in the output dataset of the "Forecast" recipe
- Add option for filling with previous value in the "Clean" recipe
- Minor bug fixes and UX enhancements

## Version 0.3.1 - Bugfix release - 2019-10

- Various bug fixes, in particular for Expert mode

## Version 0.3.0 - Improvements - 2019-05

- Remove dependency on rstan and prophet packages (thus removing Prophet model support)

## Version 0.2.0 - New features - 2019-03

- Added support of external features/regressors for Neural Network, Prophet and ARIMA models (requires availability of future values of regressors when forecasting).

## Version 0.1.0 - Initial release - 2019-01

- First pipeline for univariate forecasting of hourly to yearly time series

