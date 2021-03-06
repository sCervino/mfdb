# Init mfdb object and open connection to database
mfdb <- function(case_study_name,
                 db_params = list(),
                 destroy_schema = FALSE,
                 save_temp_tables = FALSE) {
    logger <- getLogger('mfdb')

    # Try a selection of host strings until we connect to something
    db_params <- c(db_params, list(drv = PostgreSQL(), dbname = "mf"))
    db_guesses <- list(
        list(),
        list(host = "/tmp"),
        list(host = "/tmp/pg_mfdb"),
        list(host = "/var/tmp"),
        list(host = "localhost"))
    for (guess in db_guesses) {
        db_combined <- c(guess, db_params)[!duplicated(c(guess, db_params))]
        logger$info(paste0("Trying to connect to: ", capture.output(str(db_combined)), sep = ""))
        db_connection <- tryCatch(do.call(dbConnect, db_combined), error = function (e) NULL)
        if (!is.null(db_connection)) break
    }
    if (is.null(db_connection)) {
        logger$error(paste0("Failed to connect, tried: ", capture.output(str(c(db_guesses, db_params))), sep = ""))
        stop("Could not find a local mf database")
    }

    # Create temporary mdb object and ensure we have a valid schema
    mdb <- structure(list(
            logger = logger,
            db = db_connection), class = "mfdb_temp")
    if (destroy_schema) {
        mfdb_destroy_schema(mdb)
        mdb$logger$info("Schema removed, connect again to repopulate DB.")
        dbDisconnect(mdb$db)
        return(invisible(NULL))
    }
    mfdb_update_schema(mdb)
    mfdb_update_taxonomy(mdb)

    # Look up case study ID
    case_study_id <- case_study[case_study$name == case_study_name, 'id']
    if (length(case_study_id) != 1) {
        stop("Unknown case study ", case_study_name)
    }

    # Create full mdb object
    mdb <- structure(list(
            logger = logger,
            save_temp_tables = save_temp_tables,
            case_study_id = case_study_id,
            state = new.env(),
            db = db_connection), class = "mfdb")

    invisible(mdb)
}

# Create indexes if not already there
mfdb_finish_import <- function(mdb) {
    if (!exists('index_created', where = mdb$state)) {
        mfdb_create_indexes(mdb)
        mfdb_send(mdb, "ANALYZE")
        assign('index_created', TRUE, pos = mdb$state)
    }
}

# Stop it and tidy up
mfdb_disconnect <- function(mdb) {
    mfdb_finish_import(mdb) # Might have just been an import session
    dbDisconnect(mdb$db)
}

# Perform query and return all results
mfdb_fetch <- function(mdb, ...) {
    query <- paste0(c(...), collapse = "")
    mdb$logger$debug(query)
    res <- dbSendQuery(mdb$db, query)
    out <- dbFetch(res)
    dbClearResult(res)
    return(out)
}

# Send a query without the fetch
mfdb_send <- function(mdb, ...) {
    query <- paste0(c(...), collapse = "")
    if (is.null(mdb)) {
        cat(query)
        cat("\n")
        return()
    }
    mdb$logger$debug(query)
    res <- dbSendQuery(mdb$db, query)
}

# Insert a vector row or data.frame of rows into table_name
mfdb_insert <- function(mdb, table_name, data_in, returning = "", extra = c()) {
    insert_row <- function (r) {
        res <- mfdb_send(mdb, "INSERT INTO ", paste(table_name, collapse = ""),
            " (", paste(c(names(r), names(extra)), collapse=","), ") VALUES ",
            if (is.null(nrow(r)))
                sql_quote(c(r, extra), always_bracket = TRUE)
            else
                paste0(vapply(seq_len(nrow(r)), function (i) { sql_quote(c(r[i,], extra), always_bracket = TRUE) }, ""), collapse = ","),
            (if (nzchar(returning)) paste0(c(" RETURNING ", returning), collapse = "") else ""),
            NULL)
        if (is.null(mdb)) return(0)
        out <- if (nzchar(returning)) DBI::dbFetch(res) else DBI::dbGetRowsAffected(res)
        DBI::dbClearResult(res)
        return(out)
    }
    if (!is.data.frame(data_in)) {
        # Insert single row
        return(insert_row(data_in))
    } else if (nrow(data_in) == 0) {
        # Nothing to insert
        return(0)
    } else {
        # Insert rows
        batch_size <- 1000
        return(sum(vapply(
            seq(0, nrow(data_in) %/% batch_size),
            function (i) { insert_row(data_in[(i * batch_size):min(nrow(data_in), (i+1) * batch_size - 1),]) },
            0)))
    }
}

# Update a vector row or data.frame of rows from table_name
mfdb_update <- function(mdb, table_name, data_in, returning = "", extra = c(), where = list()) {
    id_col <- paste0(table_name, '_id')

    update_row <- function (r) {
        res <- mfdb_send(mdb,
            "UPDATE ", table_name,
            " SET ",
            paste0(c(
                vapply(names(r)[names(r) != id_col], function (n) paste0(n, "=", sql_quote(r[[n]])), ""),
                vapply(names(extra), function (n) paste0(n, "=", sql_quote(extra[[n]])), ""),
                NULL
            ), collapse = ","),
            " WHERE ", table_name, "_id = ", sql_quote(r[[id_col]]),
            vapply(names(where), function (n) paste0(" AND ", n, "=", sql_quote(where[[n]])), ""),
            NULL)
        out <- if (nzchar(returning)) DBI::dbFetch(res) else DBI::dbGetRowsAffected(res)
        if (out != 1) stop("update should affect one row not ", out)
        DBI::dbClearResult(res)
        return(out)
    }

    if (!is.data.frame(data_in)) {
        # Update single row
        return(update_row(data_in))
    } else if (nrow(data_in) == 0) {
        # Nothing to update
        return(0)
    } else {
        # Update all rows in turn
        return(sum(vapply(seq(1, nrow(data_in)), function(i) update_row(data_in[i,]), 0)))
    }
}

mfdb_create_table <- function(mdb, name, desc, cols = c(), keys = c()) {
    items <- matrix(c(
        cols,
        unlist(lapply(keys, function (k) c(k, "", "")))
    ), nrow = 3)

    row_to_string <- function (i) {
        paste0("    ",
            items[1,i],
            (if (nzchar(items[2,i])) paste("\t", items[2,i])),
            (if (i == ncol(items)) "" else ","),
            (if (nzchar(items[3,i])) paste("\t--", items[3,i])),
            "\n")
    }

    mfdb_send(mdb,
        if (nzchar(desc)) paste0("-- ", desc, "\n", collapse = ""),
        "CREATE TABLE ", name, " (\n",
        vapply(1:ncol(items), row_to_string, ""),
        ")")
    if (nzchar(desc)) mfdb_send(mdb,
        "COMMENT ON TABLE ", name,
        " IS ", sql_quote(desc))
    for (i in 1:ncol(items)) {
        if (nzchar(items[3,i])) mfdb_send(mdb,
            "COMMENT ON COLUMN ", name, ".", items[1,i],
            " IS ", sql_quote(items[3,i]))
    }
}

# Execute code block within a DB transaction, roll back on error, commit otherwise
mfdb_transaction <- function(mdb, transaction) {
    mdb$logger$info("Starting transaction...")
    dbSendQuery(mdb$db, "BEGIN TRANSACTION")
    ret <- tryCatch(transaction, error = function (e) { e })
    if ("error" %in% class(ret)) {
        mdb$logger$warn("Rolling back transaction...")
        dbRollback(mdb$db)
        stop(ret)
    }
    mdb$logger$info("Committing transaction...")
    dbCommit(mdb$db)
    invisible(TRUE)
}
