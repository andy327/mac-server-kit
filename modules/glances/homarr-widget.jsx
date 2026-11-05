<Stack gap={8} p="xs">
  {status.all?.ok === false ? <Text c="red" size="xs">Glances unreachable</Text> : null}

  <Group justify="space-between" wrap="nowrap" align="center">
    <Stack gap={0}>
      <Text size="sm" fw={600}>{data.all?.system?.hostname ?? "…"}</Text>
      <Text size="xs" c="dimmed">up {data.all?.uptime ?? "…"}</Text>
      <Text size="xs" c="dimmed">{`${data.all?.processcount?.total ?? "…"} processes`}</Text>
      <Text size="xs" c="dimmed">{data.all?.system?.hr_name ?? ""}</Text>
      {(data.all?.fs ?? [])
        .filter((f) => f.mnt_point === "/System/Volumes/Data")
        .map((vol) => (
          <Text key={vol.mnt_point} size="xs" c="dimmed">
            {`${(vol.free / 1e9).toFixed(0)} GB free of ${(vol.size / 1e9).toFixed(0)} GB`}
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
        .filter((f) => f.mnt_point === "/System/Volumes/Data")
        .map((vol) => (
          <Stack key={vol.mnt_point} gap={0} align="center">
            <RingProgress size={70} thickness={6} roundCaps
              sections={[{ value: ((vol.size - vol.free) / vol.size) * 100, color: (vol.size - vol.free) / vol.size > 0.9 ? "red" : "teal" }]}
              label={<Text size="xs" ta="center">{`${(((vol.size - vol.free) / vol.size) * 100).toFixed(0)}%`}</Text>} />
            <Text size="xs" c="dimmed">DISK</Text>
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

  <SimpleGrid cols={2} spacing="xs">
    <Stack gap={2}>
      <Text size="xs" c="dimmed">
        {data.net_hist?.en0_bytes_recv_rate_per_sec?.length
          ? `↓ ${(data.net_hist.en0_bytes_recv_rate_per_sec[data.net_hist.en0_bytes_recv_rate_per_sec.length - 1][1] / 1024).toFixed(1)} KB/s`
          : "↓ …"}
      </Text>
      <Sparkline h={54} curveType="monotone" fillOpacity={0.3} color="yellow"
        data={(data.net_hist?.en0_bytes_recv_rate_per_sec ?? []).map((p) => p[1])} />
    </Stack>
    <Stack gap={2}>
      <Text size="xs" c="dimmed">
        {data.net_hist?.en0_bytes_sent_rate_per_sec?.length
          ? `↑ ${(data.net_hist.en0_bytes_sent_rate_per_sec[data.net_hist.en0_bytes_sent_rate_per_sec.length - 1][1] / 1024).toFixed(1)} KB/s`
          : "↑ …"}
      </Text>
      <Sparkline h={54} curveType="monotone" fillOpacity={0.3} color="yellow"
        data={(data.net_hist?.en0_bytes_sent_rate_per_sec ?? []).map((p) => p[1])} />
    </Stack>
  </SimpleGrid>
</Stack>
