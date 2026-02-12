###############################################################################
# Preclearance Map: Section 5 states with enacted 2010 state senate districts
###############################################################################

suppressMessages({
    library(sf)
    library(ggplot2)
    library(dplyr)
    library(tigris)
    library(here)
})

options(tigris_use_cache = TRUE)

# -- US Albers Equal Area projection ------------------------------------------
albers <- "EPSG:5070"

# -- Load US state outlines (lower 48 + AK) ----------------------------------
cat("Loading US state outlines...\n")
us_states <- states(cb = TRUE, year = 2010) %>%
    st_transform(albers)

# FIPS codes to exclude: HI (15), territories (60, 66, 69, 72, 78)
exclude_fips <- c("15", "60", "66", "69", "72", "78")
lower48 <- us_states %>% filter(!STATE %in% c("02", exclude_fips))
alaska  <- us_states %>% filter(STATE == "02")

# -- Define preclearance state shapefiles -------------------------------------
preclearance_files <- list(
    AK = here("dataverse_files/AK_Sen 2010/tl_2010_02_sldu10.shp"),
    AL = here("dataverse_files/AL_Sen 2010/tl_2010_01_sldu10.shp"),
    AZ = here("dataverse_files/AZ_Sen 2010/tl_2010_04_sldu10.shp"),
    GA = here("dataverse_files/GA_Sen 2010/tl_2010_13_sldu10.shp"),
    LA = here("dataverse_files/LA_Sen 2010/tl_2010_22_sldu10.shp"),
    MS = here("dataverse_files/MS_Sen 2010/tl_2010_28_sldu10.shp"),
    SC = here("dataverse_files/SC_Sen 2010/tl_2010_45_sldu10.shp"),
    TX = here("dataverse_files/TX_Sen 2010/tl_2010_48_sldu10.shp"),
    VA = here("dataverse_files/VA_Sen 2010/tl_2010_51_sldu10.shp")
)

# -- Read and project district shapefiles -------------------------------------
cat("Loading preclearance state senate district shapefiles...\n")
districts <- list()
for (st in names(preclearance_files)) {
    cat("  Reading", st, "...\n")
    shp <- st_read(preclearance_files[[st]], quiet = TRUE) %>%
        st_transform(albers)
    shp$state <- st
    districts[[st]] <- shp
}

# Separate Alaska districts from contiguous states
ak_districts <- districts[["AK"]]
contig_districts <- bind_rows(districts[names(districts) != "AK"])

# -- Preclearance state FIPS (for graying out non-preclearance states) --------
preclearance_fips <- c(
    "02",  # AK
    "01",  # AL
    "04",  # AZ
    "13",  # GA
    "22",  # LA
    "28",  # MS
    "45",  # SC
    "48",  # TX
    "51"   # VA
)

# Non-preclearance lower-48 states (background)
non_preclearance <- lower48 %>% filter(!STATE %in% preclearance_fips)
# Preclearance lower-48 state outlines (for a clean border)
preclearance_outlines <- lower48 %>% filter(STATE %in% preclearance_fips)

# -- Alaska inset: shift & scale to bottom-left ------------------------------
# Compute a shared centroid from the Alaska state outline for consistent shifting
ak_centroid <- st_coordinates(st_centroid(st_union(alaska)))

ak_shift <- function(geom) {
    shifted <- (geom - ak_centroid) * 0.35
    shifted <- shifted + c(-2100000, -500000)
    st_set_crs(shifted, st_crs(geom))
}

ak_districts_inset <- ak_districts %>%
    st_set_geometry(ak_shift(st_geometry(ak_districts)))

alaska_outline_inset <- alaska %>%
    st_set_geometry(ak_shift(st_geometry(alaska)))

# -- Build map ----------------------------------------------------------------
cat("Building map...\n")

highlight_fill <- "#C75146"  # muted red/coral

p <- ggplot() +
    # Non-preclearance states: light gray
    geom_sf(data = non_preclearance,
            fill = "#E8E8E8", color = "#BBBBBB", linewidth = 0.2) +
    # Preclearance state outlines (so borders are clean under districts)
    geom_sf(data = preclearance_outlines,
            fill = highlight_fill, color = "#BBBBBB", linewidth = 0.2) +
    # Contiguous preclearance districts: highlight fill with white boundaries
    geom_sf(data = contig_districts,
            fill = highlight_fill, color = "white", linewidth = 0.15) +
    # Alaska inset: outline
    geom_sf(data = alaska_outline_inset,
            fill = highlight_fill, color = "#BBBBBB", linewidth = 0.2) +
    # Alaska inset: districts
    geom_sf(data = ak_districts_inset,
            fill = highlight_fill, color = "white", linewidth = 0.15) +
    labs(title = "Section 5 Preclearance States \u2014 Enacted 2010 State Senate Districts") +
    theme_void() +
    theme(
        plot.title = element_text(hjust = 0.5, size = 16, face = "bold",
                                  margin = margin(b = 10)),
        plot.margin = margin(10, 10, 10, 10)
    )

# -- Save ---------------------------------------------------------------------
out_path <- file.path(here(), "analyses/2010s/2010s Preclearance Map/Preclearance Map/preclearance_map.png")
cat("Saving to", out_path, "\n")
ggsave(out_path, plot = p, width = 14, height = 9, dpi = 300, bg = "white")
cat("Done!\n")
