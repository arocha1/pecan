##' @name calc.metrics
##' @title calc.metrics
##' @export
##' @param model.bm
##' @param obvs.bm
##' @param var
##' @param metrics
##' @param start_year
##' @param end_year
##' @param bm
##' @param ens
##' @param model_run
##' 
##' 
##' @author Betsy Cowdery

calc.metrics <- function(model.bm, obvs.bm, var, metrics, start_year, end_year, bm, ens, model_run){
  
  dat <- align.data(model.bm, obvs.bm, var, start_year, end_year)
  
  results <- as.data.frame(matrix(NA, nrow = length(metrics$name), ncol = length(var)+1))
  colnames(results) <- c("metric", var)
  rownames(results) <- metrics$name
  results$metric <- metrics$name
  
  metric_dat <- dat[,c(paste(var, c("m", "o"),sep = "." ),"posix")]
  colnames(metric_dat)<- c("model","obvs","time")
  
  for(m in 1:length(metrics$name)){
    
    fcn <- paste0("metric.",metrics$name[m])
    
    if(tail(unlist(strsplit(fcn, "[.]")),1) =="plot"){
      filename = file.path(dirname(dirname(model_run)), 
                           paste("benchmark",metrics$name[m],var,ens$id,"pdf", sep = "."))
      do.call(fcn, args <- list(metric_dat,var,filename))
      score <- filename
      results[metrics$name[m],var] <- score
    }else{
      score <- as.character(do.call(fcn, args <- list(metric_dat,var)))
      results[metrics$name[m],var] <- score
    }
    
  } #end loop over metrics
  
  
  return(list(r = results, dat = dat))
}
