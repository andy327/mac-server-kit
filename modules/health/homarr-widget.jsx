<Box>{status.status?.loading && !data.status ? <Stack p="md"><Skeleton height={24} /><Skeleton height={60} /><Skeleton height={160} /></Stack> : status.status?.ok === false || !data.status?.windows ? <Stack p="md" gap="sm"><Alert color="red" title="Health stats unavailable">Couldn't load status.json from health-web. Check that the health-web container is running and that check-health --log has run at least once.</Alert><RefreshButton label="Retry" /></Stack> : <Stack gap="sm" p="md">
  <Group justify="space-between" wrap="nowrap">
    <Group gap="xs" wrap="nowrap">
      <Box w={10} h={10} bg={data.status.stateColor + ".6"} style={{ borderRadius: "50%" }} />
      <Text fw={600}>{data.status.name}</Text>
      <Badge color={data.status.stateColor} variant="light" size="sm">{data.status.stateLabel}</Badge>
    </Group>
    <Group gap={4} wrap="nowrap">
      <Tooltip label={"Last check " + data.status.lastCheckFull} withArrow><Text size="xs" c="dimmed">{"Checked " + data.status.lastCheck}</Text></Tooltip>
      <RefreshButton label="Refresh health stats" />
    </Group>
  </Group>

  <Stack gap={0}>
    <Text size="sm" c="dimmed">{data.status.headline.label}</Text>
    <Text fw={600} size="xl" c={data.status.state === "fail" ? "red" : undefined}>{data.status.headline.value}</Text>
    <Text size="xs" c="dimmed">{data.status.headline.detail}</Text>
  </Stack>

  <SegmentedControl bind="window" defaultValue="7d" data={["24h", "7d", "30d"]} fullWidth size="xs" aria-label="Stats window" />

  {[data.status.windows[inputs.window ?? "7d"] ?? data.status.windows["7d"]].map(w => <Stack key="stats" gap={4}>
    <SimpleGrid cols={2} spacing="lg" verticalSpacing={4}>
      {[
        { label: "Uptime", value: w.uptime },
        { label: "Outages", value: w.outages },
        { label: "Downtime", value: w.downtime },
        { label: "Longest outage", value: w.longest },
        { label: "Avg recovery", value: w.avgRecovery },
        { label: "Reboots", value: w.reboots },
        { label: "Lowest free disk", value: w.minDisk },
        { label: "Lowest free memory", value: w.minMem }
      ].map(s => <Group key={s.label} justify="space-between" wrap="nowrap" gap="xs" py={2} style={{ borderBottom: "1px solid var(--mantine-color-default-border)" }}>
        <Text size="xs" c="dimmed">{s.label}</Text>
        <Text size="sm" fw={600}>{s.value}</Text>
      </Group>)}
    </SimpleGrid>
    {w.note ? <Text size="xs" c="dimmed">{"Counting " + w.note + " (when logging began)"}</Text> : null}
  </Stack>)}

  <Stack gap={4}>
    <Group justify="space-between"><Text size="xs" c="dimmed">Last 30 days</Text><Text size="xs" c="dimmed">today</Text></Group>
    <SimpleGrid cols={30} spacing={2}>
      {(data.status.days ?? []).map(d => <Tooltip key={d.label} label={d.tip} withArrow><Box h={20} bg={d.color} style={{ borderRadius: 2 }} /></Tooltip>)}
    </SimpleGrid>
    <Group gap="md">
      {[
        { label: "up", color: "green.6" },
        { label: "under 15m down", color: "yellow.6" },
        { label: "15m+ down", color: "red.6" },
        { label: "no data", color: "gray.4" }
      ].map(k => <Group key={k.label} gap={4} wrap="nowrap"><Box w={8} h={8} bg={k.color} style={{ borderRadius: 2 }} /><Text size="xs" c="dimmed">{k.label}</Text></Group>)}
    </Group>
  </Stack>

  <Stack gap={0}>
    <Text size="sm" c="dimmed" mb={4}>Recent outages</Text>
    {(data.status.recent ?? []).length === 0 ? <Text size="sm" c="dimmed">None logged yet</Text> : (data.status.recent ?? []).slice(0, 3).map(r => <Group key={r.when} justify="space-between" wrap="nowrap" py={6} style={{ borderTop: "1px solid var(--mantine-color-default-border)" }}>
      <Text size="sm">{r.when}</Text>
      <Text size="sm" c={r.ongoing ? "red" : "dimmed"} ta="right">{r.duration + " · " + r.cause + (r.ongoing ? " (ongoing)" : "")}</Text>
    </Group>)}
  </Stack>

  {data.status.zip?.available ? <Anchor href={data.status.zip.url} target="_blank" underline="never" aria-label={"Download " + data.status.zip.name}>
    <Paper withBorder radius="md" p="xs">
      <Group justify="center" gap={6} wrap="nowrap">
        <TablerIcon name="download" size={16} />
        <Text size="sm">{"Latest incident zip (" + data.status.zip.label + ", " + data.status.zip.size + ")"}</Text>
      </Group>
    </Paper>
  </Anchor> : <Text size="xs" c="dimmed" ta="center">No incident zips yet</Text>}
</Stack>}</Box>
