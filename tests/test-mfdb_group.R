library(mfdb)
library(unittest, quietly = TRUE)
source('utils/helpers.R')

section("Can generate groupobjects", function() {
    expect_equal(
        class(mfdb_group()),
        c("mfdb_group"))

    expect_equal(
        class(mfdb_group(cows = c("daisy", "freda"))),
        c("mfdb_group"))
})

section("Can generate a numbered group", function() {
    expect_equal(
        mfdb_group_numbered("age", c(4), c(5)),
        mfdb_group(age1 = c(4), age2 = c(5)))
})

section("Can denormalise a group", function() {
    expect_equal(
        mfdb:::denormalize.mfdb_group(mfdb_group(a = c(1,"two",3), b = c(88))),
        data.frame(samp = 0,
            key = c("a", "a", "a", "b"),
            value = I(c(1, "two", 3, 88))))

    expect_equal(
        mfdb:::denormalize.mfdb_group(mfdb_group(a1 = c(1,2,3), badger = c(88, 21), a3 = c(99))),
        data.frame(samp = 0,
            key = factor(c("a1", "a1", "a1", "badger", "badger", "a3"), levels = c("a1", "badger", "a3")),
            value = I(c(1, 2, 3, 88, 21, 99))))
})

section("Can get a bootstrap sample", function() {
    expect_error(
        mfdb_bootstrap_group(2, "camel"),
        "Second argument should be a mfdb_group")
    expect_error(
        mfdb_bootstrap_group(0, mfdb_group()),
        "Count should be equal or greater than 1")

    # Single groups just get their value chosen
    expect_equal(
        mfdb:::denormalize.mfdb_bootstrap_group(mfdb_bootstrap_group(2, mfdb_group(camels = c(44), aardvarks = c(88)))),
        data.frame(
            samp = c(1, 1, 2, 2),
            key = factor(c("camels", "aardvarks", "camels", "aardvarks"), levels = c("camels", "aardvarks")),
            value = I(c(44, 88, 44, 88))))

    dn <- mfdb:::denormalize.mfdb_bootstrap_group(mfdb_bootstrap_group(2, mfdb_group(g1 = c(44, 55), g2 = c(88, 99))))
    expect_equal(dn$samp, c(1,1,1,1,2,2,2,2))
    expect_equal(dn$key, factor(c("g1", "g1", "g2", "g2", "g1", "g1", "g2", "g2")))
    expect_equal(vapply(dn[dn$key == "g1",]$value, function (x) { x %in% c("44", "55") }, logical(1)),
            c(TRUE, TRUE, TRUE, TRUE))
    expect_equal(vapply(dn[dn$key == "g2",]$value, function (x) { x %in% c("88", "99") }, logical(1)),
            c(TRUE, TRUE, TRUE, TRUE))
})