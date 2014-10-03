\name{datasets}
\alias{gear}
\alias{institute}
\alias{sampling_type}
\alias{sex}
\alias{species}
\alias{vessel}

\title{MareFrame DB Datasets}
\description{
    Data sets representing the content of taxonomies used in the database.
}

\usage{
gear
institute
sampling_type
sex
species
vessel
}

\details{
Each of the datasets will at least have
  \describe{
    \item{id}{A numeric ID to be used internally}
    \item{name}{
      An alphanumeric ID to be used when importing and reporting data.
      Can contain multiple sections separated by dots to represent a tree,
      for example: "FARMYARD.COWS.DAISY".
    }
  }
  ...and then any other data is for informational purposes only and not
  directly used by the database.
}