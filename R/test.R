# test.R
#
#' Test Function
#'
#' This function calculates deep neural network metamodel weights and generates keff predictions for all training and test data.
#' @param dataset Training and test data
#' @param ensemble.size Number of deep neural networks in the ensemble
#' @param loss Loss function
#' @param verbose Boolean (TRUE/FALSE) that determines if Test function output should be displayed
#' @param ext.dir External directory (full path)
#' @param training.dir Training directory (full path)
#' @return A list of deep neural network weights
#' @export
#' @import keras
#' @import magrittr

Test <- function(
  dataset,
  ensemble.size = 5,
  loss = 'sse',
  verbose = FALSE,
  ext.dir,
  training.dir) {

  if (missing(training.dir)) training.dir <- ext.dir

  remodel.dir <- paste0(training.dir, '/remodel')
  dir.create(remodel.dir, recursive = TRUE, showWarnings = FALSE)

  training.mae <- val.mae <- numeric()

  metamodel <- list()
  
  for (i in 1:ensemble.size) {
    metrics <- utils::read.csv(paste0(remodel.dir, '/', i, '.csv'))
    training.mae[i] <- metrics$mae[which.min(metrics$mae + metrics$val.mae)]
    val.mae[i] <- metrics$val.mae[which.min(metrics$mae + metrics$val.mae)]
    metamodel[[i]] <- load_model_hdf5(paste0(remodel.dir, '/', i, '-', metrics$epoch[which.min(metrics$mae + metrics$val.mae)], '.h5'), custom_objects = c(loss = loss))
  }

#
# minimize objective function
#
  meta.len <- length(metamodel)

  test.data <- dataset$test.data

  test.pred <- matrix(nrow = nrow(dataset$test.df), ncol = meta.len)

  test.mae <- avg <- nm <- bfgs <- sa <- numeric()

  nm.wt <- bfgs.wt <- sa.wt <- list()

  Objective <- function(x) mean(abs(test.data$keff - rowSums(test.pred * x, na.rm = TRUE))) %>% suppressWarnings()

  for (i in 1:meta.len) {

    test.pred[ , i] <- metamodel[[i]] %>% stats::predict(dataset$test.df)

    test.mae[i] <- mean(abs(test.data$keff - test.pred[ , i]))

    nm.wt[[i]] <- stats::optim(rep(1 / i, i), Objective, method = 'Nelder-Mead') %>% suppressWarnings()
    bfgs.wt[[i]] <- stats::optim(rep(1 / i, i), Objective, method = 'BFGS')
    sa.wt[[i]] <- stats::optim(rep(1 / i, i), Objective, method = 'SANN')

    avg[i] <- mean(abs(test.data$keff - rowMeans(test.pred, na.rm = TRUE)))
    nm[i] <- mean(abs(test.data$keff - rowSums(test.pred * nm.wt[[i]][[1]], na.rm = TRUE))) %>% suppressWarnings()
    bfgs[i] <- mean(abs(test.data$keff - rowSums(test.pred * bfgs.wt[[i]][[1]], na.rm = TRUE))) %>% suppressWarnings()
    sa[i] <- mean(abs(test.data$keff - rowSums(test.pred * sa.wt[[i]][[1]], na.rm = TRUE))) %>% suppressWarnings()

    if (i == 1) {
      progress.bar <- utils::txtProgressBar(min = 0, max = meta.len, style = 3)
      utils::setTxtProgressBar(progress.bar, i)
    } else {
      utils::setTxtProgressBar(progress.bar, i)
    }

  }

  close(progress.bar)
  
  utils::write.csv(data.frame(avg = avg, nm = nm, bfgs = bfgs, sa = sa), file = paste0(training.dir, '/test-mae.csv'), row.names = FALSE)

  message('Mean Training MAE = ', sprintf('%.6f', mean(training.mae)))
  message('Mean Cross-Validation MAE = ', sprintf('%.6f', mean(val.mae)))
  message('Mean Test MAE = ', sprintf('%.6f', mean(test.mae)))
  message('Ensemble Test MAE = ', sprintf('%.6f', avg[meta.len]))

  if (nm[meta.len] == bfgs[meta.len] && nm[meta.len] == sa[meta.len]) {
    msg.str <- ' (Nelder-Mead, BFGS, SA)'
  } else if (nm[meta.len] == bfgs[meta.len] && nm[meta.len] < sa[meta.len]) {
    msg.str <- ' (Nelder-Mead, BFGS)'
  } else if (nm[meta.len] == sa[meta.len] && nm[meta.len] < bfgs[meta.len]) {
    msg.str <- ' (Nelder-Mead, SA)'
  } else if (bfgs[meta.len] == sa[meta.len] && bfgs[meta.len] < nm[meta.len]) {
    msg.str <- ' (BFGS, SA)'
  } else if (nm[meta.len] < bfgs[meta.len] && nm[meta.len] < sa[meta.len]) {
    msg.str <- ' (Nelder-Mead)'
  } else if (bfgs[meta.len] < nm[meta.len] && bfgs[meta.len] < sa[meta.len]) {
    msg.str <- ' (BFGS)'
  } else if (sa[meta.len] < nm[meta.len] && sa[meta.len] < bfgs[meta.len]) {
    msg.str <- ' (SA)'
  }

  message('Ensemble Test MAE = ', sprintf('%.6f', nm[meta.len]), msg.str)

  test.min <- min(c(avg[which.min(avg)], nm[which.min(nm)], bfgs[which.min(bfgs)], sa[which.min(sa)]))

  if (test.min == nm[which.min(nm)]) {
    wt <- nm.wt[[which.min(nm)]]$par
  } else if (test.min == bfgs[which.min(bfgs)]) {
    wt <- bfgs.wt[[which.min(bfgs)]]$par
  } else if (test.min == sa[which.min(sa)]) {
    wt <- sa.wt[[which.min(sa)]]$par
  } else {
    wt <- 0
  }

  wt.len <- length(wt)

  if (wt.len < meta.len && wt[1] != 0) {

    if (wt.len == 1) {
      message('-\nTest MAE reaches a local minimum with ', wt.len, ' neural network')
    } else {
      message('-\nTest MAE reaches a local minimum with ', wt.len, ' neural networks')
    }

    message('Ensemble Test MAE = ', sprintf('%.6f', avg[wt.len]))

    if (nm[wt.len] == bfgs[wt.len] && nm[wt.len] == sa[wt.len]) {
      msg.str <- ' (Nelder-Mead, BFGS, SA)'
    } else if (nm[wt.len] == bfgs[wt.len] && nm[wt.len] < sa[wt.len]) {
      msg.str <- ' (Nelder-Mead, BFGS)'
    } else if (nm[wt.len] == sa[wt.len] && nm[wt.len] < bfgs[wt.len]) {
      msg.str <- ' (Nelder-Mead, SA)'
    } else if (bfgs[wt.len] == sa[wt.len] && bfgs[wt.len] < nm[wt.len]) {
      msg.str <- ' (BFGS, SA)'
    } else if (nm[wt.len] < bfgs[wt.len] && nm[wt.len] < sa[wt.len]) {
      msg.str <- ' (Nelder-Mead)'
    } else if (bfgs[wt.len] < nm[wt.len] && bfgs[wt.len] < sa[wt.len]) {
      msg.str <- ' (BFGS)'
    } else if (sa[wt.len] < nm[wt.len] && sa[wt.len] < bfgs[wt.len]) {
      msg.str <- ' (SA)'
    }

    message('Ensemble Test MAE = ', sprintf('%.6f', nm[meta.len]), msg.str)
    
  }

#
# set metamodel weights
#
  if (!file.exists(paste0(training.dir, '/training-data.csv')) || !file.exists(paste0(training.dir, '/test-data.csv'))) {

    training.data <- dataset$training.data

    training.pred <- matrix(nrow = nrow(dataset$training.df), ncol = wt.len)

    if (wt.len == 1) {

      training.pred[ , 1] <- metamodel[[1]] %>% stats::predict(dataset$training.df)

      training.data$avg <- training.pred[ , 1]
      training.data$nm <- training.pred[ , 1] * nm.wt[[wt.len]][[1]]
      training.data$bfgs <- training.pred[ , 1] * bfgs.wt[[wt.len]][[1]]
      training.data$sa <- training.pred[ , 1] * sa.wt[[wt.len]][[1]]

      test.data$avg <- test.pred[ , 1]
      test.data$nm <- test.pred[ , 1] * nm.wt[[wt.len]][[1]]
      test.data$bfgs <- test.pred[ , 1] * bfgs.wt[[wt.len]][[1]]
      test.data$sa <- test.pred[ , 1] * sa.wt[[wt.len]][[1]]

    } else {

      for (i in 1:wt.len) {
        training.pred[ , i] <- metamodel[[i]] %>% stats::predict(dataset$training.df)
      }

      training.data$avg <- rowMeans(training.pred[ , 1:wt.len])
      training.data$nm <- rowSums(training.pred[ , 1:wt.len] * nm.wt[[wt.len]][[1]])
      training.data$bfgs <- rowSums(training.pred[ , 1:wt.len] * bfgs.wt[[wt.len]][[1]])
      training.data$sa <- rowSums(training.pred[ , 1:wt.len] * sa.wt[[wt.len]][[1]])

      test.data$avg <- rowMeans(test.pred[ , 1:wt.len])
      test.data$nm <- rowSums(test.pred[ , 1:wt.len] * nm.wt[[wt.len]][[1]])
      test.data$bfgs <- rowSums(test.pred[ , 1:wt.len] * bfgs.wt[[wt.len]][[1]])
      test.data$sa <- rowSums(test.pred[ , 1:wt.len] * sa.wt[[wt.len]][[1]])

    }

    utils::write.csv(training.data, file = paste0(training.dir, '/training-data.csv'), row.names = FALSE)
    utils::write.csv(test.data, file = paste0(training.dir, '/test-data.csv'), row.names = FALSE)

  }

  return(wt)

}
