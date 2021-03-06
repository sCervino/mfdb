gadget_likelihood_component <- function (type, ...) {
    switch(type,
           penalty = gadget_penalty_component(...),
           understocking = gadget_understocking_component(...),
           catchstatistics = gadget_catchstatistics_component(...),
           catchdistribution = gadget_catchdistribution_component(...),
           stockdistribution = gadget_stockdistribution_component(...),
           surveyindices = gadget_surveyindices_component(...),
        stop(paste("Unknown likelihood component", type)))
}

fname <- function (dir, ...) {
    file.path(dir, paste0(c(...), collapse = ""))
}

gadget_dir_write.gadget_likelihood_component <- function(gd, obj) {
    # Either replace component with matching name, or add to end
    gadget_likelihoodfile_update <- function(gd, fname, obj) {
        likelihood <- gadget_dir_read(gd, fname)

        n <- lapply(obj, function (x) {
            # Don't let gadget_file's leak out into lists for export
            if ("gadget_file" %in% class(x)) x$filename else x
        })

        # Find component with matching name and type
        for (i in 1:(length(likelihood$components) + 1)) {
            if (i > length(likelihood$components)) break;
            if (length(likelihood$components[[i]]) == 0) next;  # e.g. empty initial component
            if (names(likelihood$components)[[i]] == "component"
                & likelihood$components[[i]]$type == n$type
                & likelihood$components[[i]]$name == n$name) break;
        }
        likelihood$components[[i]] <- n
        names(likelihood$components)[[i]] <- "component"
        if (is.null(attr(likelihood$components[[i]], "preamble"))) {
            attr(likelihood$components[[i]], "preamble") <- ""
        }
        
        gadget_dir_write(gd, likelihood)
    }
    
    ## Update mainfile and likelihood file
    gadget_mainfile_update(gd, likelihoodfiles = 'likelihood')
    gadget_likelihoodfile_update(gd, 'likelihood', obj)

    # Write out each file-based component
    for (x in obj) {
        if ("gadget_file" %in% class(x)) {
            gadget_dir_write(gd, x)
        }
    }
}

### Internal constructors for each component type

gadget_penalty_component <- function (weight = 0, name = "penalty", data = NULL) {
    if (!length(data)) {
        data = data.frame(
            switch = c("default"),
            power = c(2),
            stringsAsFactors = FALSE)
    }
    structure(list(
        name = name,
        weight = weight,
        type = "penalty",
        datafile = gadget_file(
            fname('Data', name, '.penaltyfile'),
            data = data)), class = c("gadget_penalty_component", "gadget_likelihood_component"))
}

gadget_understocking_component <- function (weight = 0, name = "understocking") {
    structure(list(
        name = name,
        weight = weight,
        type = "understocking"), class = c("gadget_understocking_component", "gadget_likelihood_component"))
}

gadget_catchstatistics_component <- function (weight = 0,
        name = "catchstatistics",
        data_function = NULL,
        data = NULL, area = NULL, age = NULL,
        fleetnames = c(), stocknames = c()) {

    prefix <- paste0('catchstatistics.', name, '.')

    if (is.null(data)) {
        stop("No data provided")
    }

    # Work out data_function based how data was generated
    if (!is.null(data_function)) {
        # It's already set, so nothing to do
    } else if (is.null(attr(data, "generator"))) {
        stop("Cannot work out the required function, and data_function not provided")
    } else if (attr(data, "generator") == "mfdb_sample_meanlength_stddev") {
        data_function <- 'lengthgivenstddev'
    } else if (attr(data, "generator") == "mfdb_sample_meanlength") {
        data_function <- 'lengthnostddev'
    } else if (attr(data, "generator") == "mfdb_sample_meanweight_stddev") {
        data_function <- 'weightgivenstddev'
    } else if (attr(data, "generator") == "mfdb_sample_meanweight") {
        data_function <- 'weightnostddev'
    } else {
        stop(paste("Unknown generator function", attr(data, "generator")))
    }

    structure(list(
        name = name,
        weight = weight,
        type = "catchstatistics",
        datafile = gadget_file(fname('Data', prefix, data_function), data=data),
        "function" = data_function,
        areaaggfile = agg_file('area', prefix, if(is.null(area)) attr(data, "area") else area),
        ageaggfile  = agg_file('age', prefix, if(is.null(age)) attr(data, "age") else age),
        fleetnames = fleetnames,
        stocknames = stocknames), class = c("gadget_catchstatistics_component", "gadget_likelihood_component"))
}

gadget_catchdistribution_component <- function (weight = 0,
        name = "catchdistribution",
        data_function = 'sumofsquares',
        data_function_params = list(),
        aggregationlevel = FALSE,
        overconsumption = FALSE,
        epsilon = 10,
        data = NULL, area = NULL, age = NULL, length = NULL,
        fleetnames = c(), stocknames = c()) {

    prefix <- paste0('catchdistribution.', name, '.')

    structure(c(list(
        name = name,
        weight = weight,
        type = "catchdistribution",
        datafile = gadget_file(fname('Data', prefix, data_function), data=data),
        "function" = data_function),
        data_function_params, list(
        aggregationlevel = if (aggregationlevel) 1 else 0,
        overconsumption = if (overconsumption) 1 else 0,
        epsilon = epsilon,
        areaaggfile = agg_file('area', prefix, if(is.null(area)) attr(data, "area") else area),
        ageaggfile  = agg_file('age', prefix, if(is.null(age)) attr(data, "age") else age),
        lenaggfile  = agg_file('len', prefix, if(is.null(length)) attr(data, "length") else length),
        fleetnames = fleetnames,
        stocknames = stocknames)), class = c("gadget_catchdistribution_component", "gadget_likelihood_component"))
}

gadget_stockdistribution_component <- function (weight = 0,
        name = "stockdistribution",
        data_function = 'sumofsquares',
        overconsumption = FALSE,
        epsilon = 10,
        data = NULL, area = NULL, age = NULL, length = NULL,
        fleetnames = c(), stocknames = c()) {
    prefix <- paste0('stockdistribution.', name, '.')

    # For stock distribution, anything in column 4 should be called stock
    if (length(names(data)) > 4) {
        names(data)[4] <- 'stock'
    }

    structure(c(list(
        name = name,
        weight = weight,
        type = "stockdistribution",
        datafile = gadget_file(fname('Data', prefix, data_function), data=data),
        "function" = data_function,
        overconsumption = if (overconsumption) 1 else 0,
        epsilon = epsilon,
        areaaggfile = agg_file('area', prefix, if(is.null(area)) attr(data, "area") else area),
        ageaggfile  = agg_file('age', prefix, if(is.null(age)) attr(data, "age") else age),
        lenaggfile  = agg_file('len', prefix, if(is.null(length)) attr(data, "length") else length),
        fleetnames = fleetnames,
        stocknames = stocknames)), class = c("gadget_stockdistribution_component", "gadget_likelihood_component"))
}

agg_file <- function (type, prefix, data) {
    if (is.null(data)) {
        # Data isn't aggregated, so leave a placeholder for now
        data <- list(all = 'X')
    } else if (class(data) == 'integer' || class(data) == 'character') {
        # Convert 1:5 to a list of 1 = 1, 2 = 2, ...
        data <- structure(
            lapply(data, function (x) x),
            names = data)
    }

    if (type == 'area') {
        # Areas should just be a => 1, b => 2, ...
        comp <- structure(
            as.list(seq_len(length(data))),
            names = names(data))
    } else if (type == 'len') {
        # Lengths should be min/max
        comp <- lapply(as.list(data), function (x) c(min(x), max(x)))
    } else {
        # Convert to list
        comp <- as.list(data)
    }

    return(gadget_file(
        fname('Aggfiles', prefix, type, '.agg'),
        components=list(comp)))
}



gadget_surveyindices_component <-
  function (weight = 0,
            name = "surveyindices",
            sitype = 'lengths',
            data_function = 'fixedslopeloglinearfit',
            biomass = 0,
            fitparameters = list(beta=1),
            data = NULL, areas = NULL, ages = NULL, lengths = NULL,
            fleetnames = c(), stocknames = c(), surveynames = c()) {
    prefix <- paste0('surveyindices.', name, '.')

    fit.type <- function(data_function,fitparameters){
        if(tolower(data_function)=='fixedslopeloglinearfit' |
           data_function == 1) {
            paste('fixedslopeloglinearfit',
                  sprintf('slope\t\t%s',fitparameters$beta),
                  sep='\n')
        } else if(tolower(data_function)=='linearfit' |
           data_function == 2) {
            'linearfit'
        } else if(tolower(data_function)=='loglinearfit' |
           data_function == 3) {
            'loglinearfit'
        } else if(tolower(data_function)=='fixedslopelinearfit' |
           data_function == 4) {
            paste('fixedslopelinearfit',
                  sprintf('slope\t\t%s',fitparameters$beta),
                  sep='\n')
        } else if(tolower(data_function)=='fixedinterceptlinearfit' |
           data_function == 5) {
            paste('fixedinterceptlinearfit',
                  sprintf('intercept\t\t%s',fitparameters$alpha),
                  sep='\n')
        } else if(tolower(data_function)=='fixedinterceptloglinearfit' |
           data_function == 6) {
            paste('fixedinterceptloglinearfit',
                  sprintf('intercept\t\t%s',fitparameters$alpha),
                  sep='\n')
        } else if(tolower(data_function)=='fixedlinearfit' |
           data_function == 7) {
            paste('fixedlinearfit',
                  sprintf('intercept\t\t%s',fitparameters$alpha),
                  sprintf('slope\t\t%s',fitparameters$beta),
                  sep='\n')
        } else if(tolower(data_function)=='fixedloglinearfit' |
           data_function == 8) {
            paste('fixedloglinearfit',
                  sprintf('intercept\t\t%s',fitparameters$alpha),
                  sprintf('slope\t\t%s',fitparameters$beta),
                  sep='\n')
        }
    }
    
    sibase <-
        list(name = name,
             weight = weight,
             type = "surveyindices",
             datafile = gadget_file(paste0(prefix, data_function),
                 data=data),
             sitype = sitype,
             biomass = biomass,
             areaaggfile = gadget_file(paste0(prefix, 'area.agg'),
                 components=list(if(is.null(areas))
                     attr(data, "areas") else areas)))
    
    
    if(sitype == 'lengths'){
        structure(c(append(sibase,list(
                         lenaggfile  = gadget_file(paste0(prefix, 'len.agg'),
                             components=list(if(is.null(lengths))
                                 attr(data, "lengths") else lengths)),
                         stocknames = stocknames,
                         fittype = fit.type(data_function,fitparameters)))),
                  class = c("gadget_surveyindices_component",
                      "gadget_likelihood_component"))
    } else if(sitype == 'age'){
        structure(c(append(sibase,list(
                         ageaggfile  = gadget_file(paste0(prefix, 'age.agg'),
                             components=list(if(is.null(ages))
                                 attr(data, "ages") else ages)),
                         stocknames = stocknames,
                         fittype = fit.type(data_function,fitparameters)))),
                  class = c("gadget_surveyindices_component",
                      "gadget_likelihood_component"))
    } else if (sitype == 'fleets'){
        structure(c(append(sibase,list(
                         lenaggfile  = gadget_file(paste0(prefix, 'len.agg'),
                             components=list(if(is.null(lengths))
                                 attr(data, "lengths") else lengths)),
                         fleetnames = fleetnames,
                         stocknames = stocknames,
                         fittype = fit.type(data_function,fitparameters)))),
                  class = c("gadget_surveyindices_component",
                      "gadget_likelihood_component"))
        
    } else if(sitype == 'acoustic'){
        structure(c(append(sibase,list(
                         surveynames = fleetnames,
                         stocknames = stocknames,
                         fittype = fit.type(data_function,fitparameters)))),
                  class = c("gadget_surveyindices_component",
                      "gadget_likelihood_component"))
    } else if(sitype == 'effort'){
        structure(c(append(sibase,list(
                         fleetnames = fleetnames,
                         stocknames = stocknames,
                         fittype = fit.type(data_function,fitparameters)))),
                  class = c("gadget_surveyindices_component",
                      "gadget_likelihood_component"))
    } else {
        warning(sprintf('Sitype %s not recognized',sitype))
    }
}
