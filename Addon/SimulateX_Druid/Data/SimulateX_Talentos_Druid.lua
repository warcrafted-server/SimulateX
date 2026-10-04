SimulateX_Talentos_Druid = {
  ["balance_druid"] = {
    specLabel = "Equilibrio",
    metric = "dps",
    referenceBuild = "p4_alliance_p3",
    variants = {
      {
        label = "nivel3",
        talents = "5102233105331303213315301031--205003012",
        dps = 14480.0,
        hps = 0,
        tps = 14203.7,
        dtps = 0,
      },
    },
    glyphs = {
      major = {
        {
          id = 40916,
          name = "Glifo de Fuego estelar",
          icon = "INV_Glyph_MajorDruid",
        },
        {
          id = 40919,
          name = "Glifo de Enjambre de insectos",
          icon = "INV_Glyph_MajorDruid",
        },
        {
          id = 40921,
          name = "Glifo de Lluvia de estrellas",
          icon = "INV_Glyph_MajorDruid",
        },
      },
      minor = {
        {
          id = 44922,
          name = "Glifo de Tifón",
          icon = "INV_Glyph_MinorDruid",
        },
      },
    },
  },
  ["feral_druid"] = {
    specLabel = "Feral",
    metric = "dps",
    referenceBuild = "p4_apl_rotation_default",
    variants = {
      {
        label = "estandar",
        talents = "-503202132322010053120230310511-205503012",
        dps = 15962.2,
        hps = 0,
        tps = 11397.3,
        dtps = 0,
      },
      {
        label = "mas_potp",
        talents = "-503202132322010053101330310511-205503012",
        dps = 15962.2,
        hps = 0,
        tps = 11397.3,
        dtps = 0,
      },
      {
        label = "nivel3",
        talents = "-553202132322010053110030310511-203503012",
        dps = 16115.0,
        hps = 0,
        tps = 11505.8,
        dtps = 0,
      },
    },
    glyphs = {
      major = {
        {
          id = 40901,
          name = "Glifo de Triturar",
          icon = "INV_Glyph_MajorDruid",
        },
        {
          id = 45601,
          name = "Glifo de Rabia",
          icon = "INV_Glyph_MajorDruid",
        },
      },
      minor = {
        {
          id = 43335,
          name = "Glifo de lo Salvaje",
          icon = "INV_Glyph_MinorDruid",
        },
      },
    },
    glyphsMissing = 1,
  },
  ["feral_tank_druid"] = {
    specLabel = "Guardián",
    metric = "tps",
    referenceBuild = "p4",
    variants = {
      {
        label = "estandar",
        talents = "-503232132322010353120300313511-20350001",
        dps = 5498.1,
        hps = 0,
        tps = 11505.2,
        dtps = 3101.2,
      },
    },
    glyphs = {
      major = {
        {
          id = 40897,
          name = "Glifo de Magullar",
          icon = "INV_Glyph_MajorDruid",
        },
        {
          id = 46372,
          name = "Glifo de Instintos de supervivencia",
          icon = "INV_Glyph_MajorDruid",
        },
        {
          id = 40896,
          name = "Glifo de Regeneración frenética",
          icon = "INV_Glyph_MajorDruid",
        },
      },
    },
  },
}
