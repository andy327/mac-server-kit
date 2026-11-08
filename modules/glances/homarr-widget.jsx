<Stack gap={8} p="xs">
  {status.all?.ok === false ? <Text c="red" size="xs">Glances unreachable</Text> : null}

  <Group justify="space-between" wrap="nowrap" align="center">
    <Stack gap={0}>
      <Text size="sm" fw={600}>{data.all?.system?.hostname ?? "…"}</Text>
      <Text size="xs" c="dimmed">up {data.all?.uptime ?? "…"}</Text>
      <Text size="xs" c="dimmed">{`${data.all?.processcount?.total ?? "…"} processes`}</Text>
      <Text size="xs" c="dimmed">{data.all?.system?.hr_name ?? ""}</Text>
      {(data.all?.fs ?? [])
        .filter((f) => f.mnt_point === "/System/Volumes/Data" || (f.mnt_point ?? "").startsWith("/Volumes/"))
        .map((vol, i, all) => (
          <Text key={vol.mnt_point} size="xs" c="dimmed">
            {`${all.length > 1 ? (vol.mnt_point === "/System/Volumes/Data" ? "SSD" : vol.mnt_point.split("/").pop()) + ": " : ""}${vol.free >= 1e12 ? (vol.free / 1e12).toFixed(1) + " TB" : (vol.free / 1e9).toFixed(0) + " GB"} free of ${vol.size >= 1e12 ? (vol.size / 1e12).toFixed(1) + " TB" : (vol.size / 1e9).toFixed(0) + " GB"}`}
          </Text>
        ))}
    </Stack>
    <Group gap="sm" wrap="nowrap">
      <Stack gap={0} align="center">
        <RingProgress size={70} thickness={6} roundCaps
          sections={[{ value: data.all?.quicklook?.cpu ?? 0, color: "blue" }]}
          label={<Text size="xs" ta="center">{data.all?.quicklook ? `${data.all.quicklook.cpu.toFixed(0)}%` : "…"}</Text>} />
        <Text size="xs" c="dimmed">CPU</Text>
      </Stack>
      <Stack gap={0} align="center">
        <RingProgress size={70} thickness={6} roundCaps
          sections={[{ value: data.all?.quicklook?.mem ?? 0, color: "orange" }]}
          label={<Text size="xs" ta="center">{data.all?.quicklook ? `${data.all.quicklook.mem.toFixed(0)}%` : "…"}</Text>} />
        <Text size="xs" c="dimmed">MEM</Text>
      </Stack>
      {(data.all?.fs ?? [])
        .filter((f) => f.mnt_point === "/System/Volumes/Data" || (f.mnt_point ?? "").startsWith("/Volumes/"))
        .map((vol, i, all) => (
          <Stack key={vol.mnt_point} gap={0} align="center">
            <RingProgress size={70} thickness={6} roundCaps
              sections={[{ value: ((vol.size - vol.free) / vol.size) * 100, color: (vol.size - vol.free) / vol.size > 0.9 ? "red" : "teal" }]}
              label={<Text size="xs" ta="center">{`${(((vol.size - vol.free) / vol.size) * 100).toFixed(0)}%`}</Text>} />
            <Text size="xs" c="dimmed">{all.length > 1 ? (vol.mnt_point === "/System/Volumes/Data" ? "SSD" : vol.mnt_point.split("/").pop()) : "DISK"}</Text>
          </Stack>
        ))}
    </Group>
  </Group>

  <Text size="xs" c="dimmed">{`CPU ${data.all?.quicklook?.cpu ?? "…"}%`}</Text>
  <Sparkline h={56} curveType="monotone" fillOpacity={0.3} color="blue"
    data={(data.cpu_hist?.user ?? []).map((p, i) => p[1] + (data.cpu_hist.system?.[i]?.[1] ?? 0))} />

  <Text size="xs" c="dimmed">{`MEM ${data.all?.quicklook?.mem ?? "…"}%`}</Text>
  <Sparkline h={56} curveType="monotone" fillOpacity={0.3} color="red"
    data={(data.mem_hist?.percent ?? []).map((p) => p[1])} />

  {[(data.all?.network ?? [])
      .filter((n) => (n.interface_name ?? "").startsWith("en"))
      .sort((a, b) => (b.bytes_all_gauge ?? 0) - (a.bytes_all_gauge ?? 0))
      .map((n) => n.interface_name)
      .concat(["en0"])
      .at(0)].map((nic) => (
    <SimpleGrid key={nic} cols={2} spacing="xs">
      {[{ dir: "recv", arrow: "↓" }, { dir: "sent", arrow: "↑" }].flatMap((d) =>
        [(data.net_hist ?? {})[nic + "_bytes_" + d.dir + "_rate_per_sec"] ?? []].map((h) => (
          <Stack key={d.dir} gap={2}>
            <Text size="xs" c="dimmed">
              {h.length ? `${d.arrow} ${(h[h.length - 1][1] / 1024).toFixed(1)} KB/s (${nic})` : `${d.arrow} …`}
            </Text>
            <Sparkline h={54} curveType="monotone" fillOpacity={0.3} color="yellow" data={h.map((p) => p[1])} />
          </Stack>
        )))}
    </SimpleGrid>
  ))}
</Stack>
