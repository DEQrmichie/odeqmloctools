#' Get NHDplus HR info as a dataframe
#'
#' The function will query the NHDplus High Resolution (HR) feature service and
#' return a dataframe of info for the flowline. x and y coordinates are used to
#' select the reach.
#'
#' The function will query the NHDplus High Resolution (HR) REST service from
#' USGS and return a dataframe containing the flowline info. The supplied x and
#' y coordinates (longitude and latitude) are used to select the closest
#' flowline record and calculate the measure value. Only the closest flowline
#' within the search distance is returned. If there are no flowlines within the
#' search distance the returned dataframe will contain all NAs. If two or more
#' flowline records are equal distance to x and y only the first record will be
#' returned.
#'
#' The NDHplus High Resolution feature service is at \url{https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer/2/}.
#'
#' @param .data A data frame
#' @param x The longitude in decimal degrees. Required. Accepts a vector.
#' @param y The latitude in decimal degrees. Required. Accepts a vector.
#' @param crs The coordinate reference system for x and y. Same format as
#'            \code{\link[sf:st_crs]{sf::st_crs}}. Typically entered using
#'            the numeric EPSG value. Accepts a vector.
#' @param search_dist The maximum search distance around x and y to look for
#'        features. Measured in meters. Default is 100.
#' @export
#' @return sf object

get_nhdplus_df <- function(.data, x, y, crs, search_dist = 100){

  if (length(.data[[deparse(substitute(x))]]) != length(.data[[deparse(substitute(y))]])) {
    stop("x and y must have the same number of elements")
  }

  df <- purrr::pmap_dfr(list(.data[[deparse(substitute(x))]],
                             .data[[deparse(substitute(y))]],
                             .data[[deparse(substitute(crs))]]),
                        search_dist = search_dist,
                          .f = get_nhdplus_df_)
  # reset row numbers
  row.names(df) <- NULL

  df2 <- cbind(.data, df)

  return(df2)

}

#' Non vectorized version of get_nhdplushr. This is what purrr calls.
#'
#' @noRd
get_nhdplus_df_ <- function(x, y, crs, search_dist = 100) {

  # Test data
  # y <- 42.09359
  # x <- -122.3813
  # search_dist <- 100
  # crs <- 4236

  # Idaho (error)
  # y = 44.24176
  # x = -116.9416

  # feature service out crs, WGS84
  fs_crs <- 4326

  query_url  <- "https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer/2/query?"


  request <- httr::GET(url = URLencode(paste0(query_url, "geometryType=esriGeometryPoint&geometry=",x,",",y,
                                              "&inSR=",crs,"&outFields=*&returnGeometry=true",
                                              "&distance=",search_dist,"&units=esriSRUnit_Meter&returnIdsOnly=false&f=GeoJSON"), reserved = FALSE))


  response <- httr::content(request, as = "text", encoding = "UTF-8")

  reach_df <- geojsonsf::geojson_sf(response) %>%
    sf::st_zm()

  # get the site, make sf object
  site <- sf::st_as_sf(data.frame(Longitude = x, Latitude = y),
                       coords = c("Longitude", "Latitude"), crs = crs)

  if (httr::http_error(request) | NROW(reach_df) == 0) {
    warning("Error, NA returned")

    return(dplyr::mutate(site,
                         Measure = NA_real_,
                         Snap_Lat = NA_real_,
                         Snap_Long = NA_real_,
                         Snap_Distance = units::set_units(NA_real_, m)) %>%
             cbind(nhdplushr_na()) %>%
             sf::st_transform(site, crs = fs_crs))
  }

  # get the site, make sf object
  site <- sf::st_transform(site, crs = sf::st_crs(reach_df))

  reach_df$snap_distance <- sf::st_distance(site, reach_df, by_element = TRUE)

  #reach_df <- reach_df %>%
    #dplyr::select(dplyr::everything(-geometry), geometry)

  # return row that is closest
  reach_df2 <- reach_df %>%
    dplyr::slice_min(snap_distance, with_ties = FALSE) %>%
    dplyr::mutate(HWTYPE = as.numeric(HWTYPE),
                  HWNODESQKM = as.numeric(HWNODESQKM))

  df_meas <- get_measure2(line = reach_df2, point = site, id = "REACHCODE",
                          return_df = TRUE, nhdplus = TRUE)
  reach_df3 <- cbind(reach_df2, df_meas)

  return(reach_df3)

}




