package com.tuluobo.ggesim.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp

private val BaseTypography = Typography()

private fun TextStyle.withoutTracking(): TextStyle = copy(letterSpacing = 0.sp)

val Typography = Typography(
    displayLarge = BaseTypography.displayLarge.withoutTracking(),
    displayMedium = BaseTypography.displayMedium.withoutTracking(),
    displaySmall = BaseTypography.displaySmall.withoutTracking(),
    headlineLarge = BaseTypography.headlineLarge.withoutTracking(),
    headlineMedium = BaseTypography.headlineMedium.withoutTracking(),
    headlineSmall = BaseTypography.headlineSmall.withoutTracking(),
    titleLarge = BaseTypography.titleLarge.withoutTracking(),
    titleMedium = BaseTypography.titleMedium.withoutTracking(),
    titleSmall = BaseTypography.titleSmall.withoutTracking(),
    bodyLarge = BaseTypography.bodyLarge.withoutTracking(),
    bodyMedium = BaseTypography.bodyMedium.withoutTracking(),
    bodySmall = BaseTypography.bodySmall.withoutTracking(),
    labelLarge = BaseTypography.labelLarge.withoutTracking(),
    labelMedium = BaseTypography.labelMedium.withoutTracking(),
    labelSmall = BaseTypography.labelSmall.withoutTracking()
)
