import { Center, Container, Heading, Link, ListItem, UnorderedList } from '@chakra-ui/react';
import { Header3 } from '~/components/HelpText/Headers';
import { KuwoFAQ } from '~/faq/KuwoFAQ';
import { OtherFAQ } from '~/faq/OtherFAQ';
import { QQMusicFAQ } from '~/faq/QQMusicFAQ';

export function FaqTab() {
  return (
    <Container pb={10} maxW="container.md">
      <Center>
        <Heading as="h2">常见问题解答</Heading>
      </Center>
      <Header3>答疑目录</Header3>
      <UnorderedList>
        <ListItem>
          <Link href="#faq-qqmusic">QQ 音乐</Link>
        </ListItem>
        <ListItem>
          <Link href="#faq-kuwo">酷我音乐</Link>
        </ListItem>
        <ListItem>
          <Link href="#faq-other">其它问题</Link>
        </ListItem>
      </UnorderedList>
      <Header3 id="faq-qqmusic">QQ 音乐</Header3>
      <QQMusicFAQ />
      <Header3 id="faq-kuwo">酷我音乐</Header3>
      <KuwoFAQ />
      <Header3 id="faq-other">其它问题</Header3>
      <OtherFAQ />
    </Container>
  );
}
